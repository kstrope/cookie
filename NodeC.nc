/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"

configuration NodeC{
}
implementation {
    components MainC;
    components Node;
    components new TimerMilliC() as PeriodicTimerC;
    components new TimerMilliC() as SendTimerC;
    components new TimerMilliC() as RecieveTimerC;
    components new AMReceiverC(AM_PACK) as GeneralReceive;
    
    components TransportC;
    Node.Transport -> TransportC;
    TransportC.ConfirmedC -> ConfirmedC;
    TransportC.SocketsC -> SocketsC;

    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;
	

    components new ListC(pack, 64) as MarkedPacketsC;
    Node.MarkedPackets -> MarkedPacketsC;

    components new ListC(Neighbor, 64) as NeighborsC;
    Node.Neighbors -> NeighborsC;
    
    components new ListC(Neighbor, 64) as NeighborsDroppedC;
    Node.NeighborsDropped -> NeighborsDroppedC;

    components new ListC(LinkState, 64) as RoutingTableC;
    Node.RoutingTable -> RoutingTableC;

    components new ListC(LinkState, 64) as ConfirmedC;
    Node.Confirmed -> ConfirmedC;

    components new ListC(LinkState, 64) as TentativeC;
    Node.Tentative -> TentativeC;

    components new ListC(LinkState, 64) as TempC;
    Node.Temp -> TempC;

    components new ListC(socket_store_t, 10) as SocketsC;
    Node.Sockets -> SocketsC;
    
    components new ListC(socket_store_t, 10) as TempSocketsC;
    Node.TempSockets -> TempSocketsC;

    components new HashmapC(int, 64) as nextTableC;
    Node.nextTable -> nextTableC;

    components RandomC as Random;
    Node.Random -> Random;

    Node.PeriodicTimer -> PeriodicTimerC;
    Node.SendTimer -> SendTimerC;
    Node.RecieveTimer -> RecieveTimerC;

    components LocalTimeMilliC;
    Node.LocalTime -> LocalTimeMilliC;
}
