#include "../../includes/packet.h"
#include "../../includes/socket.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"

module TransportP {
	provides interface Transport;

	uses interface List<socket_store_t> as Sockets;
	uses interface List<socket_store_t> as TempSockets;
	uses interface SimpleSend as Sender;
	uses interface List<LinkState> as Confirmed;
}

implementation {
   /**
    * Get a socket if there is one available.
    * @Side Client/Server
    * @return
    *    socket_t - return a socket file descriptor which is a number
    *    associated with a socket. If you are unable to allocated
    *    a socket then return a NULL socket_t.
    */
   command socket_t Transport.socket() {
	socket_t fd;
	uint8_t i;
	socket_store_t insert;
	if (call Sockets.size() < MAX_NUM_OF_SOCKETS) {
		insert.fd = call Sockets.size();
		insert.effectiveWindow = 128;
		insert.lastWritten = 0;
		insert.nextExpected = 0;
		insert.lastSent = 0;
		insert.lastRcvd = 0;
		insert.lastRead = 0;
		fd = call Sockets.size();
		for(i = 0; i < 128; i++)
		{
			insert.sendBuff[i] = 255;
			insert.rcvdBuff[i] = 255;
		}
		call Sockets.pushback(insert);
	}
	else {
		dbg(TRANSPORT_CHANNEL, "return NULL\n");
		return NULL;
	}
	return fd;
   }

   /**
    * Bind a socket with an address.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       you are binding.
    * @param
    *    socket_addr_t *addr: the source port and source address that
    *       you are biding to the socket, fd.
    * @Side Client/Server
    * @return error_t - SUCCESS if you were able to bind this socket, FAIL
    *       if you were unable to bind.
    */
   command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
	socket_store_t temp;
	socket_addr_t tempAddr;
	error_t success;
	bool found = FALSE;
	while (!call Sockets.isEmpty()) {
		temp = call Sockets.front();
		call Sockets.popfront();
		if (temp.fd == fd && !found) {
			tempAddr.port = addr->port;
			tempAddr.addr = addr->addr;
			temp.src = tempAddr.port;
			found = TRUE;
			//dbg(TRANSPORT_CHANNEL, "fd found, inserting addr of node %d port %d\n", tempAddr.addr, tempAddr.port);
			call TempSockets.pushfront(temp);
		}
		else {
			call TempSockets.pushfront(temp);
		}
	}
	while (!call TempSockets.isEmpty()) {
		call Sockets.pushfront(call TempSockets.front());
		call TempSockets.popfront();
	}
	if (found == TRUE)
		return success = SUCCESS;
	else
		return success = FAIL;
	
   }

   /**
    * Checks to see if there are socket connections to connect to and
    * if there is one, connect to it.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that is attempting an accept. remember, only do on listen. 
    * @side Server
    * @return socket_t - returns a new socket if the connection is
    *    accepted. this socket is a copy of the server socket but with
    *    a destination associated with the destination address and port.
    *    if not return a null socket.
    */
   command socket_t Transport.accept(socket_t fd) {
	socket_store_t temp;
	socket_t rt;
	bool found = FALSE;
	uint16_t at;
	uint16_t i = 0;
	for(i = 0; i < call Sockets.size(); i++)
	{
		temp = call Sockets.get(i);
		if(temp.fd == fd && found == FALSE && temp.state == LISTEN)
		{
			found = TRUE;
			at = i;
		}
	}
	if(found == TRUE)
	{
		//return socket_t with stuff
		temp = call Sockets.get(at);
		rt = temp.fd;
		return rt;
	}
	else
	{
		return NULL;
	}
			
   }

   /**
    * Write to the socket from a buffer. This data will eventually be
    * transmitted through your TCP implimentation.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that is attempting a write.
    * @param
    *    uint8_t *buff: the buffer data that you are going to wrte from.
    * @param
    *    uint16_t bufflen: The amount of data that you are trying to
    *       submit.
    * @Side For your project, only client side. This could be both though.
    * @return uint16_t - return the amount of data you are able to write
    *    from the pass buffer. This may be shorter then bufflen
    */
            command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {
                socket_store_t temp, temp2;
		LinkState destination;
		pack write;
                uint16_t sockLen;
		uint8_t arr[2];
                uint16_t i,j,at,buffcount,next;
                uint8_t buffsize, buffable, buffto;
                bool found = FALSE;
		write.src = TOS_NODE_ID;
		write.protocol = PROTOCOL_TCP;
		sockLen = call Sockets.size();
                for(i = 0; i < sockLen; i++)
                {
                        temp = call Sockets.get(i);
                        if(temp.fd == fd && found == FALSE)
                        {
                                at = i;
                                found = TRUE;
                        }
                }
                if(found == FALSE)
                {
                        return 0;
                }
                else
                {
                        temp = call Sockets.get(at);
                        if(bufflen > (128 - temp.lastWritten))
                        {
                                buffable = 128 - temp.lastWritten;
                        }
                        else
                        {
                                buffable = bufflen;
                        }
                        buffcount = 0;
                        buffto = temp.lastWritten + buffable;
                        j = temp.lastSent;
                        for(i = 0; i < buffto; i++)
                        {
                                //temp.lastWritten++;
                                temp.sendBuff[i] = j;
                                j++;
                                buffcount++;
                        }
			write.dest = temp.dest.addr;
			write.TTL = MAX_TTL;
			//printf("write.dest is %d\n", write.dest);
                        temp.lastWritten = i;
			//printf("lastwritten is %d\n", temp.lastWritten);
                        temp.lastSent = j;
			temp.flag = 4;
			write.seq = i;
			memcpy(write.payload, &temp, (uint8_t) sizeof(temp));

			for (i = 0; i < call Confirmed.size(); i++)
			{
				destination = call Confirmed.get(i);
				if (write.dest == destination.Dest)
				{
					//printf("found dest\n");
					next = destination.Next;
				}
			}			
			temp.lastWritten = 0;
                        while(!call Sockets.isEmpty())
                        {
                                temp2 = call Sockets.front();
                                if(temp.fd == temp2.fd)
                                {
                                        call TempSockets.pushfront(temp);
                                }
                                else
                                {
                                        call TempSockets.pushfront(temp2);
                                }
                                call Sockets.popfront();
                        }
                        while(!call TempSockets.isEmpty())
                        {
                                call Sockets.pushfront(call TempSockets.front());
                                call TempSockets.popfront();
                        }
			//printf("sending tooooo: %d\n", next);
			call Sender.send(write, next);

                        return buffcount;
                }
        }
   /**
    * This will pass the packet so you can handle it internally. 
    * @param
    *    pack *package: the TCP packet that you are handling.
    * @Side Client/Server 
    * @return uint16_t - return SUCCESS if you are able to handle this
    *    packet or FAIL if there are errors.
    */
	command error_t Transport.receive(pack* package) {
		error_t result;
		if(package->protocol != PROTOCOL_TCP)
		{
			result = FAIL;
			return result;
		}
		else
		{
			result = SUCCESS;
			return result;
		}
	}

   /**
    * Read from the socket and write this data to the buffer. This data
    * is obtained from your TCP implimentation.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that is attempting a read.
    * @param
    *    uint8_t *buff: the buffer that is being written.
    * @param
    *    uint16_t bufflen: the amount of data that can be written to the
    *       buffer.
    * @Side For your project, only server side. This could be both though.
    * @return uint16_t - return the amount of data you are able to read
    *    from the pass buffer. This may be shorter then bufflen
    */
    
        command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen) {
                socket_store_t temp, temp2;
                uint16_t sockLen = call Sockets.size();
                uint16_t i, j, at, buffcount;
                uint8_t buffsize, buffable, buffto;
                bool found = FALSE;
                for(i = 0; i < sockLen; i++)
                {
                        temp = call Sockets.get(i);
                        if(temp.fd == fd && found == FALSE)
                        {
                                at = i;
                                found = TRUE;
                        }
                }
                if(found == FALSE)
                {
                        return 0;
                }
                else
                {
                        //do buffer things
                        temp = call Sockets.get(at);
                        buffcount = 0;
			//printf("effectivewindow is %d\n", temp.effectiveWindow);
                        if(bufflen > temp.effectiveWindow)
                        {
                                buffable = temp.effectiveWindow;
                        }
                        else
                        {
                                buffable = bufflen;
                        }
                        j = temp.nextExpected;
			//printf("buffable is %d\n", buffable);
			j = 0;
                        for(i = 0; i < buffable; i++)
                        {
				//printf("buff is %d\n", buff[i]);
                                temp.rcvdBuff[j] = j + temp.lastRcvd;
                                //temp.sendBuff[i] = 255;
                                j++;
                                buffcount++;
                                if(temp.effectiveWindow > 0)
                                {
                                        temp.effectiveWindow--;
                                }
                        }
                        temp.lastRcvd = i;
                        temp.lastWritten = 0;
                        if(temp.effectiveWindow == 0)
                        {
                                temp.nextExpected = 0;
                        }
                        else
                        {
                                temp.nextExpected = j+1;
                        }

			//dbg(TRANSPORT_CHANNEL, "printing out rcvdBuff\n");
			for(i = 0; i < temp.lastRcvd; i++)
			{
				dbg(TRANSPORT_CHANNEL,"%d\n", temp.rcvdBuff[i]);
				if(i > 0 && i%6 == 0)
				{
					//printf("\n");
				}
				temp.rcvdBuff[i] = 255;
				temp.effectiveWindow++;
			}
			//printf("\n");

			//pushing stuff
                        while(!call Sockets.isEmpty())
                        {
                                temp2 = call Sockets.front();
                                if(temp.fd != temp2.fd)
                                {
                                        call TempSockets.pushfront(call Sockets.front());
                                }
                                else
                                {
				        call TempSockets.pushfront(temp);
                                }
                                call Sockets.popfront();
                        }
                        while(!call TempSockets.isEmpty())
                        {
                                call Sockets.pushfront(call TempSockets.front());
                                call TempSockets.popfront();
                        }
                        return buffcount;
                }
        }

   /**
    * Attempts a connection to an address.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are attempting a connection with. 
    * @param
    *    socket_addr_t *addr: the destination address and port where
    *       you will atempt a connection.
    * @side Client
    * @return socket_t - returns SUCCESS if you are able to attempt
    *    a connection with the fd passed, else return FAIL.
    */
   command error_t Transport.connect(socket_t fd, socket_addr_t * addr) {
		pack syn;
		error_t success;
		bool sent;
		socket_store_t temp, temp2;
		uint16_t next;
		uint16_t i;
		LinkState destination;
		syn.dest = addr->addr;
		syn.src = TOS_NODE_ID;
		//dbg(TRANSPORT_CHANNEL, "TOS_NODE_ID = %d\n", TOS_NODE_ID);
		syn.seq = 1;
		syn.TTL = MAX_TTL;
		syn.protocol = 4;
		temp = call Sockets.get(fd);
		temp.flag = 1;
		temp.dest.port = addr->port;
		temp.dest.addr = addr->addr;

		while(!call Sockets.isEmpty())
		{
			temp2 = call Sockets.front();
			if(temp.fd == temp2.fd)
			{
				call TempSockets.pushfront(temp);
			}
			else
			{
				call TempSockets.pushfront(temp2);
			}
			call Sockets.popfront();
		}
		while(!call TempSockets.isEmpty())
		{
			call Sockets.pushfront(call TempSockets.front());
			call TempSockets.popfront();
		}

		memcpy(syn.payload, &temp, (uint8_t) sizeof(temp));
		
		for (i = 0; i < call Confirmed.size(); i++) {
			destination = call Confirmed.get(i);
			if (syn.dest == destination.Dest) {
				next = destination.Next;
				sent = TRUE;
			}
		}
		
		call Sender.send(syn, next);
		if (sent == TRUE)
			return success = SUCCESS;
		else
			return success = FAIL;
	}

   /**
    * Closes the socket.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are closing. 
    * @side Client/Server
    * @return socket_t - returns SUCCESS if you are able to attempt
    *    a closure with the fd passed, else return FAIL.
    */
	command error_t Transport.close(socket_t fd)
	{
		socket_store_t temp;
		uint16_t i, at;
		error_t success;
		bool able = FALSE;
		while(!call Sockets.isEmpty())
		{
			temp = call Sockets.front();
			call Sockets.popfront();
			if(temp.fd == fd)
			{
				temp.state = CLOSED;
				able = TRUE;
			}
			call TempSockets.pushfront(temp);
		}
		while(!call TempSockets.isEmpty())
		{
			call Sockets.pushfront(call TempSockets.front());
			call TempSockets.popfront();
		}
		if(able == TRUE)
		{
			return success = SUCCESS;
		}
		else
		{
			return success = FAIL;
		}
	}

   /**
    * A hard close, which is not graceful. This portion is optional.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are hard closing. 
    * @side Client/Server
    * @return socket_t - returns SUCCESS if you are able to attempt
    *    a closure with the fd passed, else return FAIL.
    */
   command error_t Transport.release(socket_t fd) {}

   /**
    * Listen to the socket and wait for a connection.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are hard closing. 
    * @side Server
    * @return error_t - returns SUCCESS if you are able change the state 
    *   to listen else FAIL.
    */
	command error_t Transport.listen(socket_t fd)
	{
		socket_store_t temp;
		enum socket_state tempState;
		error_t success;
		bool found = FALSE;
		while (!call Sockets.isEmpty()) {
			temp = call Sockets.front();
			call Sockets.popfront();
			if (temp.fd == fd && !found) {
				tempState = LISTEN;
				temp.state = tempState;
				found = TRUE;
				//dbg(TRANSPORT_CHANNEL, "fd found, changing state to %d\n", temp.state);
				call TempSockets.pushfront(temp);
			}
			else {
				call TempSockets.pushfront(temp);
			}
		}
		while (!call TempSockets.isEmpty()) {
			call Sockets.pushfront(call TempSockets.front());
			call TempSockets.popfront();
		}
		if (found == TRUE)
			return success = SUCCESS;
		else
			return success = FAIL;
	}
}
