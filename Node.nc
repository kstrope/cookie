/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/socket.h"
#define INFINITY 65535

//define the type Neighbor with the Node ID and number of pings to it
typedef nx_struct Neighbor {
   nx_uint16_t Node;
   nx_uint16_t pingNumber;
}Neighbor;

typedef nx_struct LinkState {
   nx_uint16_t Dest;
   nx_uint16_t Cost;
   nx_uint16_t Next;
   nx_uint16_t Seq;
   //nx_uint16_t from;
   nx_uint8_t Neighbors[64];
   nx_uint16_t NeighborsLength;
}LinkState;

module Node{
   uses interface Boot;
   
   //list of packets to determine if a node has seen or sent this packet before
   uses interface List<pack> as MarkedPackets;
   //timer to use to fire packets
   uses interface Timer<TMilli> as PeriodicTimer;
   //timers for clients/servers
   uses interface Timer<TMilli> as SendTimer;
   uses interface Timer<TMilli> as RecieveTimer;
   //random number used for timer to make sure it's spaced
   uses interface Random as Random;
   //list of neighboring nodes as seen by current node
   uses interface List<Neighbor> as Neighbors;
   //list of removed nodes from the neighbor list
   uses interface List<Neighbor> as NeighborsDropped;
   //list of nodes and their costs 
   uses interface List<Neighbor> as NeighborCosts;
   //routing table to be used by nodes
   uses interface List<LinkState> as RoutingTable;
   //confirmed table for algo
   uses interface List<LinkState> as Confirmed;
   //tentative table for algo
   uses interface List<LinkState> as Tentative;
   uses interface List<LinkState> as Temp;

   //number of sockets for node, whether server or client
   uses interface List<socket_store_t> as Sockets;
   
   uses interface List<socket_store_t> as TempSockets;

   uses interface Hashmap<int> as nextTable;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;
   uses interface Transport;
   uses interface LocalTime<TMilli>;

}

implementation{
   pack sendPackage;
   uint16_t seqCounter = 0;
   uint16_t accessCounter = 0;
   uint32_t difference = 0;
   uint32_t algopush = 0;
   uint32_t sendTime = 0;
   uint32_t recieveTime = 0;
   uint32_t attemptTime = 4294967295;
   uint32_t RTT = 0;
   bool connected = FALSE;
   bool recieveAck = FALSE;
   socket_t fd;
   int16_t globalTransfer = 0;
   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
   //puts a packet into the list at the top
   void pushPack(pack Package);
   //finds a packet in the list
   bool findPack(pack *Package);
   //access neighbor list
   void accessNeighbors();
   //starts to flood the LSP packet
   void floodLSP();
   //runs dijkstra's algorithm for shortest path
   void algorithm();
   void findNext();
   //void algorithm(uint16_t Dest, uint16_t Cost, uint16_t Next, uint8_t * Nbors, uint16_t Length);

   void printLSP();

   event void Boot.booted(){
      uint32_t initial;
      uint32_t change;
      call AMControl.start();
      dbg(GENERAL_CHANNEL, "Booted\n");
      //create an initial time to start firing from between 0-999 milliseconds
      initial = call Random.rand32() % 1000;
      //change is the interval to fire between each fire from 10000-25000 milliseconds
      change = 10000 + (call Random.rand32() % 15000);
      //start the timer
      call PeriodicTimer.startPeriodicAt(initial, change);
      //dbg(GENERAL_CHANNEL, "Timer started at %d, firing interval %d\n", initial, change);
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void PeriodicTimer.fired() {
	accessNeighbors();
	if (accessCounter > 1 && accessCounter % 3 == 0 && accessCounter < 16){
		floodLSP();
		//algorithm(TOS_NODE_ID, 0, 0, 0, call Neighbors.size());
		//if (TOS_NODE_ID == 1) 		
			//printLSP();
		//findNext();
	}
	if (accessCounter > 1 && accessCounter % 20 == 0 && accessCounter < 61)
		algorithm();
   }

   event void RecieveTimer.fired() {
	socket_store_t temp;
	uint16_t num;
	uint16_t i;
	uint16_t at;
	bool found = FALSE;
	//dbg(TRANSPORT_CHANNEL, "RecieveTimer fired for this node!\n");
	for(i = 0; i < call Sockets.size(); i++)
	{
        	temp = call Sockets.get(i);
        	if(temp.fd == fd && found == FALSE/* && temp.state == ESTABLISHED*/)
        	{
                	found = TRUE;
                	at = i;
			//printf("at is %d", at);
        	}
	}
	if (found) {
		//dbg(TRANSPORT_CHANNEL, "Recieve found?\n");
		temp = call Sockets.get(at);
		//num = call Transport.read(temp.fd, 0, temp.lastWritten);
	}
   }

   event void SendTimer.fired() {
	socket_store_t temp;
	uint16_t num;
	uint16_t i;
	uint16_t at;
	uint16_t size;
	bool found;
	found = FALSE;
	//dbg(TRANSPORT_CHANNEL, "SendTimer fired for this node!\n");
	//printf("size is %d\n", call Sockets.size());
	for(i = 0; i < call Sockets.size(); i++)
	{
		temp = call Sockets.get(i);
		//printf("temp fd is %d, global fd is %d\n", temp.fd, fd);
		if(temp.fd == fd && found == FALSE/* && temp.state == ESTABLISHED*/)
		{
			found = TRUE;
			at = i;
		}
		//printf("is here\n");
	}
	if (found) {
		temp = call Sockets.get(at);
	}
	//printf("also here\n");
	if (/*temp.lastWritten == 0 && */found)
	{
		//printf("even here\n");
		while (globalTransfer > 0) {
			size = call Transport.write(fd, 0, globalTransfer);
			globalTransfer = globalTransfer - size;
		}
	}
   }


   event void AMControl.stopDone(error_t err){}

	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
		//dbg(FLOODING_CHANNEL, "Packet Received\n");
		if(len==sizeof(pack))
		{
			LinkState DESTI, DEST;
			uint16_t NEXT,SEND,x,y;
			//creates a message with the payload, or message, of the recieved packet
			pack* myMsg=(pack*) payload;
			//check to see if this packet needs to be dropped, either through checking to see if the TTL expired, or if it was listed in the list of sent or seen packets
			if((myMsg->TTL <= 0) || findPack(myMsg)){
				//drops packet by doing nothing and not sending out a new packet
			}
			//else, check to see if the packet is checking for neighbors, deal with it seperately
			else if(myMsg->dest == AM_BROADCAST_ADDR) {
				bool found;
				bool match;
				uint16_t length;
				uint16_t i = 0;
				Neighbor Neighbor1,Neighbor2,NeighborCheck;
				//if the packet is sent to ping for neighbors
				if (myMsg->protocol == PROTOCOL_PING){
					//send a packet that expects replies for neighbors
					//dbg(NEIGHBOR_CHANNEL, "Packet sent from %d to check for neighbors\n", myMsg->src);
					makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, myMsg->TTL-1, PROTOCOL_PINGREPLY, myMsg->seq, (uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
					pushPack(sendPackage);
					call Sender.send(sendPackage, myMsg->src);
				}
				//if the packet is sent to ping for replies
				else if (myMsg->protocol == PROTOCOL_PINGREPLY){ 
					//update ping number, search and see if the neighbor was found
					//dbg(NEIGHBOR_CHANNEL, "Packet recieved from %d, replying\n", myMsg->src);
					length = call Neighbors.size();
					found = FALSE;
					for (i = 0; i < length; i++){
						Neighbor2 = call Neighbors.get(i);
						//dbg(GENERAL_CHANNEL, "Pings at %d = %d\n", Neighbor2.Node, Neighbor2.pingNumber);
						if (Neighbor2.Node == myMsg->src) {
							//dbg(NEIGHBOR_CHANNEL, "Node found, adding %d to list\n", myMsg->src);
							//reset the ping number if found to keep it from being dropped
							Neighbor2.pingNumber = 0;
							found = TRUE;
						}
					}
				}
				//if the packet is sent to find other nodes
				else if (myMsg->protocol == PROTOCOL_LINKSTATE) {
					//store the LSP in a list of structs
					LinkState LSP;
					LinkState temp;
					Neighbor Ntemp;
					bool end, from, good, found, push;
					uint16_t j,size,k;
					uint16_t count;
					uint16_t* arr;
					//bool same;
					//bool replace; 
					count = 0;
					end = TRUE;
					from = FALSE;
					good = TRUE;
					found = FALSE;
					push = FALSE;
					i = 0;
					if(call RoutingTable.isEmpty())
					{
						temp.Dest = TOS_NODE_ID;
						temp.Cost = 0;
						temp.Next = TOS_NODE_ID;
						temp.Seq = 0;
						temp.NeighborsLength = call Neighbors.size();
						for(i = 0; i < temp.NeighborsLength; i++)
						{
							Ntemp = call Neighbors.get(i);
							temp.Neighbors[i] = Ntemp.Node;
						}
						call RoutingTable.pushfront(temp);
					}
					if (myMsg->src != TOS_NODE_ID){
						arr = myMsg->payload;
						size = call RoutingTable.size();
						LSP.Dest = myMsg->src;
						LSP.Seq = myMsg->seq;
						LSP.Cost = MAX_TTL - myMsg->TTL;
						///if (TOS_NODE_ID == 1)
							//dbg(GENERAL_CHANNEL, "myMsg->TTL is %d, LSP.Cost is %d, good is %d, from %d\n", myMsg->TTL, LSP.Cost, good, myMsg->src);
						i = 0;
						count = 0;
						while (arr[i] > 0) {
							LSP.Neighbors[i] = arr[i];
							count++;
							i++;
						}
						LSP.Next = 0;
						LSP.NeighborsLength = count;
						if (!call RoutingTable.isEmpty())
						{
							while(!call RoutingTable.isEmpty())
							{
								temp = call RoutingTable.front();
								if((temp.Dest == LSP.Dest) && (LSP.Cost <= temp.Cost))
								{
									call RoutingTable.popfront();
									push = TRUE;
									found = TRUE;
								}
								else if((temp.Dest == LSP.Dest) && (LSP.Cost > temp.Cost))
								{
									call Temp.pushfront(call RoutingTable.front());
									call RoutingTable.popfront();
									push = FALSE;
									found = TRUE;
								}
								else
								{
									call Temp.pushfront(call RoutingTable.front());
									call RoutingTable.popfront();
								}
							}
							while(!call Temp.isEmpty())
							{
								call RoutingTable.pushfront(call Temp.front());
								call Temp.popfront();
							}
						}
						if (call RoutingTable.isEmpty())
						{
							call RoutingTable.pushfront(LSP);
						}
						else if(found == FALSE)
						{
							call RoutingTable.pushfront(LSP);
						}
						else if (push == TRUE)
						{
							call RoutingTable.pushfront(LSP);
						}
						//printLSP();
						seqCounter++;
						makePack(&sendPackage, myMsg->src, AM_BROADCAST_ADDR, myMsg->TTL-1, PROTOCOL_LINKSTATE, seqCounter, (uint8_t *)myMsg->payload, (uint8_t) sizeof(myMsg->payload));
						pushPack(sendPackage);
						call Sender.send(sendPackage, AM_BROADCAST_ADDR);
					}
				}
				//if we didn't find a match
				if (!found && myMsg->protocol != PROTOCOL_LINKSTATE && myMsg->protocol != PROTOCOL_TCP)
				{
					//add it to the list, using the memory of a previous dropped node
					Neighbor1 = call NeighborsDropped.get(0);
					//check to see if already in list
					length = call Neighbors.size();
					for (i = 0; i < length; i++)
					{
						NeighborCheck = call Neighbors.get(i);
						if (myMsg->src == NeighborCheck.Node)
						{
							match = TRUE;
						}
					}
					if (match == TRUE)
					{
						//already in the list, no need to repeat
					}
					else
					{
						//not in list, so we're going to add it
						//dbg(NEIGHBOR_CHANNEL, "%d not found, put in list\n", myMsg->src);
						//LinkState temp;
						Neighbor1.Node = myMsg->src;
						Neighbor1.pingNumber = 0;
						call Neighbors.pushback(Neighbor1);
						
					}
				}
			} 
 			//else, check to see if the packet reached it's destination and see what the purpose/protocal of the packet was 
			else if((myMsg->dest == TOS_NODE_ID) && myMsg->protocol == PROTOCOL_PING) {
				//uint16_t NEXT,x;
				//LinkState DEST;
				NEXT = 0;
				//when protocal = PROTOCAL_PING, the packet was sent as a ping, and not a reply
				dbg(FLOODING_CHANNEL, "Packet is at destination! Package Payload: %s, Sending PING_REPLY to %d\n", myMsg->payload, myMsg->src);
				//make another packet that's the reply from the ping
				makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_PINGREPLY, seqCounter, (uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
				//increase the sequence number of the next packet that will be sent
				seqCounter++;
				//put the packet into the list
				pushPack(sendPackage);
				
				for(x = 0; x < call Confirmed.size(); x++)
				{
					DEST = call Confirmed.get(x);
					if(myMsg->src == DEST.Dest)
					{
						NEXT = DEST.Next;
					}
				}
				if(NEXT == 0)
				{
					//NEXT = AM_BROADCAST_ADDR;
				}
				//send the new packet
				dbg(ROUTING_CHANNEL, "meant for %d, sending to %d\n", myMsg->src, NEXT);
				call Sender.send(sendPackage, NEXT);
			}
			else if((myMsg->dest == TOS_NODE_ID) && myMsg->protocol == PROTOCOL_PINGREPLY) {
				//the packet is at the right destination, and it is simply a reply, we can stop sending the packet here
				dbg(FLOODING_CHANNEL, "Recieved a reply it was delivered from %d!\n", myMsg->src);
			}
			else if (myMsg->dest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_TCP) {
				uint16_t i;
				uint16_t j;
				uint16_t* arr;
				uint16_t RTT1;
				uint16_t buffLen;
				bool found;
 				LinkState destination;
 				uint16_t next;
 				pack packet;
				socket_store_t* temp;
				socket_store_t temp2;
				socket_store_t packetTemp;
				socket_store_t change;
				socket_addr_t tempAddr;
 				temp = myMsg->payload;
 				tempAddr = temp->dest;
 				//dbg(TRANSPORT_CHANNEL, "protocol is TCP! temp->flag = %d, temp->src = %d, temp->dest.port = %d, temp->dest.addr = %d\n", temp->flag, temp->src, tempAddr.port, tempAddr.addr);
 				for (i = 0; i < call Sockets.size(); i++) {
			         	temp2 = call Sockets.get(i);
			         	if (temp->flag == 1 && tempAddr.port == temp2.src && temp2.state == LISTEN && tempAddr.addr == TOS_NODE_ID) {
                 			dbg(TRANSPORT_CHANNEL, "Syn packet recieved into port %d\n", temp2.src);
                 			packet.dest = myMsg->src;
                 			packet.src = TOS_NODE_ID;
                 			packet.seq = myMsg->seq + 1;
                 			packet.TTL = myMsg->TTL;
                 			packet.protocol = 4;
                 			packetTemp = call Sockets.get(i);
                 			packetTemp.flag = 2;
                 			packetTemp.dest.port = temp->src;
                 			packetTemp.dest.addr = myMsg->src;

                 			memcpy(packet.payload, &packetTemp, (uint8_t) sizeof(packetTemp));

                 			for (j = 0; j < call Confirmed.size(); j++) {
                         			destination = call Confirmed.get(j);
                         			if (packet.dest == destination.Dest)
                                 			next = destination.Next;
                 			}
                			 while (!call Sockets.isEmpty()) {
                         			change = call Sockets.front();
                         			call Sockets.popfront();
                         			if (change.fd == i && !found) {
                                 			change.state = SYN_RCVD;
                                 			found = TRUE;
                                 			call TempSockets.pushfront(change);
                         			}
                         			else {
                                 			call TempSockets.pushfront(change);
                         			}
                 			}
                 			while (!call TempSockets.isEmpty() ) {
                         			call Sockets.pushfront(call TempSockets.front());
                         			call TempSockets.popfront();
                 			}
                 			call Sender.send(packet, next);
         			}
         			if (temp->flag == 2 && tempAddr.port == temp2.src) {
                			recieveTime = call LocalTime.get();
				        RTT = recieveTime - sendTime;
        				dbg(TRANSPORT_CHANNEL, "SynAck packet recived into port %d, send = %d, recieve = %d, RTT = %d\n", temp2.src,  sendTime, recieveTime, RTT);
        				packet.dest = myMsg->src;
        				packet.src = TOS_NODE_ID;
        				packet.seq = myMsg->seq + 1;
        				packet.TTL = myMsg->TTL;
        				packet.protocol = 4;
        				packetTemp = call Sockets.get(i);
       					packetTemp.flag = 3;
        				packetTemp.dest.port = temp->src;
        				packetTemp.dest.addr = myMsg->src;

        				memcpy(packet.payload, &packetTemp, (uint8_t) sizeof(packetTemp));

         				for (j = 0; j < call Confirmed.size(); j++) {
                 				destination = call Confirmed.get(j);
                 				if (packet.dest == destination.Dest)
                         				next = destination.Next;
                				}
        				while (!call Sockets.isEmpty()) {
                				change = call Sockets.front();
                				call Sockets.popfront();
                 				if (change.fd == i && !found) {
                        				change.state = ESTABLISHED;
                        				found = TRUE;
							connected = TRUE;
                        				call TempSockets.pushfront(change);
                				}
                				else {
                        				call TempSockets.pushfront(change);
                				}
        				}
       					while (!call TempSockets.isEmpty() ) {
                				call Sockets.pushfront(call TempSockets.front());
                				call TempSockets.popfront();
        				}
					call SendTimer.startPeriodic(25000);
        				call Sender.send(packet, next);
				}
				if (temp->flag == 3 && tempAddr.port == temp2.src) {
        				while (!call Sockets.isEmpty()) {
                				change = call Sockets.front();
                				call Sockets.popfront();
                				if (change.fd == i && !found) {
                       					change.state = ESTABLISHED;
                       					found = TRUE;
							connected = TRUE;
                       					call TempSockets.pushfront(change);
                				}
               					else {
                       					call TempSockets.pushfront(change);
                				}
        				}
        				while (!call TempSockets.isEmpty() ) {
						call Sockets.pushfront(call TempSockets.front());
						call TempSockets.popfront();
                        		}
					call RecieveTimer.startPeriodic(100000);
                        		dbg(TRANSPORT_CHANNEL, "Ack1 packet recieved into port %d with RTT %d\n", temp2.src, RTT);
              				}
				}
				if (temp->flag == 4 /*&& tempAddr.port == temp2.src && temp->state == ESTABLISHED && temp2.state == ESTABLISHED*/) {
					arr = myMsg->payload;
					buffLen = myMsg->seq;
					dbg(TRANSPORT_CHANNEL, "Recievced data from %d!\n", myMsg->src); 
					call Transport.read(temp->fd, temp->sendBuff, buffLen);
					packet.dest = myMsg->src;
					packet.src = TOS_NODE_ID;
					packet.seq = myMsg->seq + 1;
					packet.TTL = myMsg->TTL;
					packet.protocol = 4;
					packetTemp = call Sockets.get(i);
					packetTemp.flag = 5;
					packetTemp.dest.port = temp->src;
					packetTemp.dest.addr = myMsg->src;
					packetTemp.nextExpected = buffLen + 1;
					
					memcpy(packet.payload, &packetTemp, (uint8_t) sizeof(packetTemp));

					for (j = 0; j < call Confirmed.size(); j++) {
        					destination = call Confirmed.get(j);
        					if (packet.dest == destination.Dest)
                					next = destination.Next;
        					}
					while (!call Sockets.isEmpty()) {
        					change = call Sockets.front();
        					call Sockets.popfront();
        					if (change.fd == i && !found) {
							change.lastAck = buffLen + 1;
                					found = TRUE;
                					call TempSockets.pushfront(change);
        					}
        					else {
        					        call TempSockets.pushfront(change);
        					}
					}
					while (!call TempSockets.isEmpty() ) {
        					call Sockets.pushfront(call TempSockets.front());
        					call TempSockets.popfront();
					}
					call Sender.send(packet, next);
				}
				if (temp->flag == 5 /*&& tempAddr.port == temp2.src && temp->state == ESTABLISHED && temp2.state == ESTABLISHED*/) {
					dbg(TRANSPORT_CHANNEL, "Recieved dataAck from %d!\n", myMsg->src);
					recieveAck = TRUE;
				}
				if (temp->flag == 6 && tempAddr.port == temp2.src) {
					while (!call Sockets.isEmpty()) {
                				change = call Sockets.front();
                				call Sockets.popfront();
                				if (change.fd == i && !found) {
                       					change.state = CLOSED;
                       					found = TRUE;
                       					call TempSockets.pushfront(change);
                				}
               					else {
                       					call TempSockets.pushfront(change);
                				}
        				}
        				while (!call TempSockets.isEmpty() ) {
						call Sockets.pushfront(call TempSockets.front());
						call TempSockets.popfront();
                        		}
                        		dbg(TRANSPORT_CHANNEL, "Closed.\n");
				} 
			}
			else {
				//uint16_t y,SEND;
				//LinkState DESTI;
				SEND = 0;
				//all else, wrong destination, flood the packet
				makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
				pushPack(sendPackage);
				for(y=0; y < call Confirmed.size(); y++)
				{
					DESTI = call Confirmed.get(y);
					if(myMsg->dest == DESTI.Dest)
					{
						SEND = DESTI.Next;
					}
				}
				if(SEND == 0)
				{
					//SEND = AM_BROADCAST_ADDR;
				}
				dbg(ROUTING_CHANNEL, "meant for %d, sending to %d\n", myMsg->dest, SEND);
				call Sender.send(sendPackage, SEND);
			}
			return msg;
		}
		else
		{
		//all else, we dunno what the packet was to do
		dbg(GENERAL_CHANNEL, "Unknown Packet Use, Error with: %d\n", len);
		return msg;
		}
	}


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
	uint16_t i,next;
	LinkState temp;
	next = 0;
	for(i = 0; i < call Confirmed.size(); i++)
	{
		temp = call Confirmed.get(i);
		if (temp.Dest == destination)
		{
			next = temp.Next;
		}
	}
	if(next == 0)
	{
		//next = AM_BROADCAST_ADDR;
	}
      dbg(GENERAL_CHANNEL, "PING EVENT, destination %d; sending to %d \n", destination, next);
      makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, next);
   }

   event void CommandHandler.printNeighbors(){
	uint16_t i = 0;
	uint16_t length = call Neighbors.size();
	Neighbor beingPrinted;
	if (length == 0){
		dbg(NEIGHBOR_CHANNEL, "No neighbors exist\n");	
	}
	else {
		for (i = 0; i < length; i++){
			beingPrinted = call Neighbors.get(i);
			dbg(NEIGHBOR_CHANNEL, "Neighbor at %d\n", beingPrinted.Node, i);
			}
	}
   }

   event void CommandHandler.printRouteTable(){
	uint16_t k = 0;
	LinkState temp;
	dbg(ROUTING_CHANNEL, "Table for %d\n", TOS_NODE_ID);
	for (k = 0; k < call Confirmed.size(); k++) {
		temp = call Confirmed.get(k);
		dbg(ROUTING_CHANNEL, "Dest: %d, Cost: %d, Next: %d\n", temp.Dest, temp.Cost, temp.Next);
	}
   }

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

	event void CommandHandler.setTestServer(uint16_t port){
		socket_addr_t address;
		fd = call Transport.socket();
		address.addr = TOS_NODE_ID;
		address.port = port;
		if (call Transport.bind(fd, &address) == SUCCESS) {
			//dbg(TRANSPORT_CHANNEL, "yay\n");
			if (call Transport.listen(fd) == SUCCESS) {
        			//dbg(TRANSPORT_CHANNEL, "listening...\n");
        			//if (connected == TRUE)
				//call RecieveTimer.startPeriodic(100000);
			}
		}
	}

	event void CommandHandler.setTestClient(uint16_t dest, uint16_t sourcePort, uint16_t destPort, uint16_t transfer){
		pack syn;
		uint8_t i;
		uint16_t test;
		socket_store_t synSocket;
		socket_addr_t address;
		socket_addr_t serverAddress;
		fd = call Transport.socket();
		address.addr = TOS_NODE_ID;
		address.port = sourcePort;
		serverAddress.addr = dest;
		serverAddress.port = destPort;
		globalTransfer = transfer;

		if (call Transport.bind(fd, &address) == SUCCESS) {
			sendTime = call LocalTime.get();
			//send SYN packet
			if (call Transport.connect(fd, &serverAddress) == SUCCESS) {
				//call SendTimer.startPeriodic(15000);
        			//dbg(TRANSPORT_CHANNEL, "Node %d set as client with source port %d, and destination %d at their port %d\n", TOS_NODE_ID, sourcePort, dest, destPort);
			}
		}
	}

	event void CommandHandler.testClose(uint16_t dest, uint16_t sourcePort, uint16_t destPort) {
		pack fin;
		bool sent;
		socket_store_t temp, temp2;
		uint16_t next;
		uint16_t i;
		LinkState destination;
		fin.dest = dest;
		fin.src = TOS_NODE_ID;
		//dbg(TRANSPORT_CHANNEL, "TOS_NODE_ID = %d\n", TOS_NODE_ID);
		fin.seq = 1;
		fin.TTL = MAX_TTL;
		fin.protocol = 4;
		temp = call Sockets.get(fd);
		temp.state = CLOSED;
		temp.flag = 6;
		temp.dest.port = dest;
		temp.dest.addr = destPort;
		
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

		for (i = 0; i < call Confirmed.size(); i++) {
			destination = call Confirmed.get(i);
			if (fin.dest == destination.Dest) {
				next = destination.Next;
				sent = TRUE;
			}
		}
		
		call Sender.send(fin, next);
		dbg(TRANSPORT_CHANNEL, "Closed.\n");
	}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(uint8_t client, char* username){
		uint8_t i;
		bool printUser;
		i = 0;
		printUser = TRUE;
		printf("Username: ");
		while(printUser) {
			if (username[i] == '\n') {
				printf("%c", username[i]);
				printUser = FALSE;
			}
			else {
				printf("%c", username[i]);
				i++;
			}
		}
		printf("Client Number: %d\n", client);
	}

   event void CommandHandler.message(char* message) {
		uint8_t i;
		bool printUser;
		i = 0;
		printUser = TRUE;
		printf("Message: ");
		while(printUser) {
        		if (message[i] == '\n') {
                		printf("%c", message[i]);
                		printUser = FALSE;
        		}
        		else {
                		printf("%c", message[i]);
                		i++;
        		}
		}
	}

   event void CommandHandler.whisper(uint16_t recipient, char* message) {
		uint8_t i;
 		bool printUser;
 		i = 0;
 		printUser = TRUE;
 		printf("Whisper for %d: ", recipient);
 		while(printUser) {
         		if (message[i] == '\n') {
                 		printf("%c", message[i]);
                 		printUser = FALSE;
         		}
         		else {
                 		printf("%c", message[i]);
                 		i++;
         		}
 		}
	}

   event void CommandHandler.list() {
		printf("insert list here\n");
	}

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }

   void printLSP()
   {
      LinkState temp;
      uint16_t i, j;
      for(i=0; i < call RoutingTable.size(); i++)
		{
			temp = call RoutingTable.get(i);
			dbg(GENERAL_CHANNEL, "LSP from %d, Cost: %d, Next: %d, Seq: %d, Count; %d\n", temp.Dest, temp.Cost, temp.Next, temp.Seq, temp.NeighborsLength);
			for(j=0; j<temp.NeighborsLength; j++)
			{
				//dbg(GENERAL_CHANNEL, "Neighbor at %d\n", temp.Neighbors[j]);
			}
		}
		//dbg(GENERAL_CHANNEL, "size is %d\n", call RoutingTable.size());
	}




   void accessNeighbors() {
	//make a packet to send to check neighbors
	pack Pack;
	//test message to be sent
	char* message;
	//increase the access counter
	accessCounter++;
	//dbg(NEIGHBOR_CHANNEL, "Neighbors accessed, %d is checking.\n", TOS_NODE_ID);
	//check to see if neighbors have been found at all
	if (!(call Neighbors.isEmpty())) {
		uint16_t length = call Neighbors.size();
		uint16_t pings = 0;
		Neighbor NeighborNode;
		uint16_t i = 0;
		Neighbor temp; 
		//increase the number of pings in the neighbors in the list. if the ping number is greater than 3, drop the neighbor
		for (i = 0; i < length; i++){
			temp = call Neighbors.get(i);
			temp.pingNumber = temp.pingNumber + 1;
			pings = temp.pingNumber;
			//dbg(ROUTING_CHANNEL, "Pings at %d: %d\n", temp.Node, pings);
			if (pings > 3){
				NeighborNode = call Neighbors.removeFromList(i);
				dbg(NEIGHBOR_CHANNEL, "Node %d dropped due to more than 3 pings\n", NeighborNode.Node);
				call NeighborsDropped.pushfront(NeighborNode);
				i--;
				length--;
			}
		}					
	}
	//ping the list of Neighbors
	message = "pinged neighbors!\n";
	makePack(&Pack, TOS_NODE_ID, AM_BROADCAST_ADDR, 2, PROTOCOL_PING, 1, (uint8_t*) message, (uint8_t) sizeof(message));
	//add the packet to the packet list
	pushPack(Pack);
	//send the packet
	call Sender.send(Pack, AM_BROADCAST_ADDR);
   }

	void pushPack(pack Package) {
		//check to see if the list is full; if so, remove the oldest node
		if (call MarkedPackets.isFull()) {
			call MarkedPackets.popfront();
		}
		call MarkedPackets.pushback(Package);
	}

	bool findPack(pack *Package) {
		uint16_t size = call MarkedPackets.size();
		uint16_t i = 0;
		pack match;
		for (i = 0; i < size; i++) {
			match = call MarkedPackets.get(i);
			if((match.src == Package->src) && (match.dest == Package->dest) && (match.seq == Package->seq)) {
				return TRUE;
			}
		}
		return FALSE;
	}
	
	void floodLSP(){
		//run to flood LSPs, sending info of this node's direct neighbors
		pack LSP;
		LinkState O;
		//dbg(ROUTING_CHANNEL, "LSP Initial Flood from %d\n", TOS_NODE_ID);
		//check to see if there are neighbors to at all
		if (!call Neighbors.isEmpty()){
			uint16_t i = 0;
			uint16_t length = call Neighbors.size();
			uint16_t directNeighbors[length+1];
			Neighbor temp;
			//dbg(ROUTING_CHANNEL, "length = %d/n", length);

			//move the neighbors into the array
			for (i = 0; i < length; i++) {
				temp = call Neighbors.get(i);
				directNeighbors[i] = temp.Node;
			}
			//set a negative number to tell future loops to stop!
			directNeighbors[length] = 0;
			//directNeighbors[length+1] = TOS_NODE_ID;
			//dbg(ROUTING_CHANNEL, "this should be 0: %d\n", directNeighbors[length]);
			//start flooding the packet
			makePack(&LSP, TOS_NODE_ID, AM_BROADCAST_ADDR, MAX_TTL-1, PROTOCOL_LINKSTATE, seqCounter++, (uint16_t*)directNeighbors, (uint16_t) sizeof(directNeighbors));
			pushPack(LSP);
			call Sender.send(LSP, AM_BROADCAST_ADDR);
		}
	}

	void removefunction(uint16_t i)
	{
		LinkState temp, temp2;
		temp2 = call Tentative.get(i);
		while(!call Tentative.isEmpty())
		{
			temp = call Tentative.front();
			if(temp.Dest == temp2.Dest)
			{
				call Tentative.popfront();
			}
			else
			{
				call Temp.pushfront(call Tentative.front());
				call Tentative.popfront();
			}
		}
		while(!call Temp.isEmpty())
		{
			call Tentative.pushback(call Temp.front());
			call Temp.popfront();
		}
	}

	void algorithm()
	{
		int nodesize[20];
		int size = call RoutingTable.size();
		int mn = 20;
		int i,j,nexthop,cost[mn][mn],distance[mn],plist[mn];
		int visited[mn],ncount,mindistance,nextnode;

		int start_node = TOS_NODE_ID;
		bool aMatrix[mn][mn];

		LinkState temp, temp2;

		for(i = 0; i < mn; i++)
		{
			for(j = 0; j < mn; j++)
			{
				aMatrix[i][j] = FALSE;
			}
		}
		
		for(i = 0; i < size; i++)
		{
			temp = call RoutingTable.get(i);
			for(j = 0; j < temp.NeighborsLength; j++)
			{
				aMatrix[temp.Dest][temp.Neighbors[j]] = TRUE;
			}
		}

		for(i = 0; i < mn; i++)
		{
			for(j = 0; j < mn; j++)
			{
				if(aMatrix[i][j] == FALSE)
				{
					cost[i][j] = INFINITY;
				}
				else
				{
					cost[i][j] = 1;
				}
			}
		}
		if(TOS_NODE_ID == 1){
		for(i = 0; i < mn; i++)
		{
			for(j = 0; j < mn; j++)
			{
				//printf("i=%d, j=%d, cost=%d\n", i, j, cost[i][j]);
			}
		}
		}

		for(i = 0; i < mn; i++)
		{
			distance[i] = cost[start_node][i];
			plist[i] = start_node;
			visited[i] = 0;
		}
		
		distance[start_node] = 0;
		visited[start_node] = 1;
		ncount = 1;

		while(ncount < mn - 1)
		{
			mindistance = INFINITY;
			for(i = 0; i < mn; i++)
			{
				if(distance[i] <= mindistance && visited[i] == 0)
				{
					mindistance = distance[i];
					nextnode = i;
				}
			}
			visited[nextnode] = 1;
			for(i = 0; i < mn; i++)
			{
				if(visited[i] == 0)
				{
					if(mindistance + cost[nextnode][i] < distance[i])
					{
						distance[i] = mindistance + cost[nextnode][i];
						plist[i] = nextnode;
					}
				}
			}
			ncount++;
		}

		for(i = 0; i < mn; i++)
		{
			nexthop = TOS_NODE_ID;
			if(distance[i] != INFINITY)
			{
				if(i != start_node)
				{
					j = i;
					do {
						if(j != start_node)
						{
							nexthop = j;
						}
						j = plist[j];
					} while(j != start_node);
				}
				else
				{
					nexthop = start_node;
				}
				if(nexthop != 0)
				{
					call nextTable.insert(i, nexthop);
				}
			}
		}
		if(call Confirmed.isEmpty())
		{
			for(i = 1; i <= 20; i++)
			{
				temp2.Dest = i;
				temp2.Cost = cost[TOS_NODE_ID][i];
				temp2.Next = call nextTable.get(i);
				call Confirmed.pushfront(temp2);
				//dbg(GENERAL_CHANNEL, "confirmed size: %d\n", call Confirmed.size());
			}
		}
		
	}
		
}
