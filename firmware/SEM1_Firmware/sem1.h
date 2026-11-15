// The two functions the sketch (SEM1_Firmware.ino) calls. Both live in main.cpp.
#pragma once

void sem1Setup();  // start everything once: meter, clock, history log, WiFi, web page
void sem1Loop();   // keep everything running; called over and over
