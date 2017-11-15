#include "../includes/am_types.h"

configuration TransportC {
	provides interface Transport;
}

implementation {
	components TransportP;
	Transport = TransportP;

	components new ListC(socket_store_t, 10) as SocketsC;
	TransportP.Sockets -> SocketsC;

	components new ListC(socket_store_t, 10) as TempSocketsC;
	TransportP.TempSockets -> TempSocketsC;
}
