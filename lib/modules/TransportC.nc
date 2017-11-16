#include "../includes/am_types.h"

configuration TransportC {
	provides interface Transport;
	uses interface List<LinkState> as ConfirmedC;
	uses interface List<socket_store_t> as SocketsC;
}

implementation {
	components TransportP;
	Transport = TransportP;

	TransportP.Confirmed = ConfirmedC;
	TransportP.Sockets = SocketsC;

	components new SimpleSendC(AM_PACK);
	TransportP.Sender -> SimpleSendC;

	//components new ListC(socket_store_t, 10) as SocketsC;
	//TransportP.Sockets -> SocketsC;

	components new ListC(socket_store_t, 10) as TempSocketsC;
	TransportP.TempSockets -> TempSocketsC;
}
