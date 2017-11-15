#include "../../includes/packet.h"
#include "../../includes/socket.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"

module TransportP {
	provides interface Transport;

	uses interface List<socket_store_t> as Sockets;
	uses interface List<socket_store_t> as TempSockets;
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
	socket_store_t insert;
	if (call Sockets.size() < MAX_NUM_OF_SOCKETS) {
		insert.fd = call Sockets.size();
		fd = call Sockets.size();
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
			temp.dest = tempAddr;
			found = TRUE;
			dbg(TRANSPORT_CHANNEL, "fd found, inserting addr of node %d port %d\n", tempAddr.addr, tempAddr.port);
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
   command socket_t Transport.accept(socket_t fd) {}

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
   command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {}

   /**
    * This will pass the packet so you can handle it internally. 
    * @param
    *    pack *package: the TCP packet that you are handling.
    * @Side Client/Server 
    * @return uint16_t - return SUCCESS if you are able to handle this
    *    packet or FAIL if there are errors.
    */
   command error_t Transport.receive(pack* package) {
	
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
   command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen) {}

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
   command error_t Transport.close(socket_t fd) {}

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
   command error_t Transport.listen(socket_t fd) {
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
			dbg(TRANSPORT_CHANNEL, "fd found, changing state to %d\n", temp.state);
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
