# MC Protocol (RS-232) to Modbus RTU over TCP gateway

This solution is written to make possible to communicate with FX1,FX2,FX3 PLCs (including China clones) connected by RS-232 cable to computer via network by the following scheme:
```
Host ---(Modbus RTU over TCP)---> Computer ---(RS-232 Cable)---> PLC
```

So, it works as simply gateway server. Gateway wait data from Modbus on TCP, then ask PLC via MC Protocol and gives results back.
This allows to get any data (D,C,T,Y,M) from PLC via network.
Now it is only Modbus function 03 is supported. 
Should works on Windows and Linux. Prebuild binaries will be available later.
