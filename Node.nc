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

module Node{
   uses interface Boot;
   
   //list of packets to determine if a node has seen or sent this packet before
   uses interface List<pack> as MarkedPackets;
   //timer to use to fire packets
   uses interface Timer<TMilli> as PeriodicTimer;
   //random number used for timer to make sure it's spaced
   uses interface Random as Random;
   //list of neighboring nodes as seen by current node
   uses interface List<neighbor*> as Neighbors;
   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;

}

implementation{
   pack sendPackage;
	uint16_t seqCounter = 0;
   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
   //puts a packet into the list at the top
   void pushPack(pack Package);
   //finds a packet in the list
   bool findPack(pack *Package);

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
      dbg(GENERAL_CHANNEL, "Timer started at %d, firing interval %d\n", initial, change);
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
	
   }


   event void AMControl.stopDone(error_t err){}

	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
		dbg(FLOODING_CHANNEL, "Packet Received\n");
		if(len==sizeof(pack)){
			//creates a message with the payload, or message, of the recieved packet
			pack* myMsg=(pack*) payload;
			//check to see if this packet needs to be dropped, either through checking to see if the TTL expired, or if it was listed in the list of sent or seen packets
			if((myMsg->TTL == 0) || findPack(myMsg)){
				//drops packet by doing nothing and not sending out a new packet
			  //else, check to see if the packet reached it's destination and see what the purpose/protocal of the packet was
			} else if((myMsg->dest == TOS_NODE_ID) && myMsg->protocol == PROTOCOL_PING) {
				//when protocal = PROTOCAL_PING, the packet was sent as a ping, and not a reply
				dbg(FLOODING_CHANNEL, "Packet is at destination! Package Payload: %s\n", myMsg->payload);
				//make another packet that's the reply from the ping
				makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_PINGREPLY, seqCounter, (uint8_t *) myMsg->payload, sizeof(myMsg->payload));
				//increase the sequence number of the next packet that will be sent
				seqCounter++;
				//put the packet into the list
				pushPack(sendPackage);
				//send the new packet
				call Sender.send(sendPackage, AM_BROADCAST_ADDR);
			} else if((myMsg->dest == TOS_NODE_ID) && myMsg->protocol == PROTOCOL_PINGREPLY) {
				//the packet is at the right destination, and it is simply a reply, we can stop sending the packet here
				dbg(FLOODING_CHANNEL, "Recieved a reply it was delivered from %d!\n", myMsg->src);
			} else {
				//all else, wrong destination, flood the packet
				makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));
				dbg(FLOODING_CHANNEL, "Recieved packet from %d, meant for %d, TTL is %d. Rebroadcasting\n", myMsg->src, myMsg->dest, myMsg->TTL);
				pushPack(sendPackage);
				call Sender.send(sendPackage, AM_BROADCAST_ADDR);
			}
			return msg;
		}
		else {
		//all else, we dunno what the packet was to do
		dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
		return msg;
		}
	}


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, AM_BROADCAST_ADDR);
   }

   event void CommandHandler.printNeighbors(){}

   event void CommandHandler.printRouteTable(){}

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
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
}
