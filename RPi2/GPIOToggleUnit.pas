unit GPIOToggleUnit;

{$mode objfpc}{$H+}

{ Advanced example - Dedicated CPU                                             }
{                                                                              }
{ This file contains the GPIO functionality for our dedicated CPU example.     }
{                                                                              }

interface


uses
 BCM2836,
 GlobalConst,
 GlobalConfig,
 Platform;
  
 
procedure GPIOPinOn(Pin:LongWord);
procedure GPIOPinOff(Pin:LongWord);

implementation

procedure GPIOPinOn(Pin:LongWord);
var
 Reg:LongWord;
 Shift:LongWord;
 
begin
 {Get Shift}
 Shift:=Pin mod 32;

 {Get Register}
 Reg:=BCM2836_GPSET0 + ((Pin div 32) * SizeOf(LongWord));
 
 {Memory Barrier}
 DataMemoryBarrier; {Before the First Write}
 
 {Write Register}
 PLongWord(GPIO_REGS_BASE + Reg)^:=(BCM2836_GPSET_MASK shl Shift);

end;

procedure GPIOPinOff(Pin:LongWord);
var
 Reg:LongWord;
 Shift:LongWord;
 
begin
 {Get Shift}
 Shift:=Pin mod 32;

 {Get Register}
 Reg:=BCM2836_GPCLR0 + ((Pin div 32) * SizeOf(LongWord));
 
 {Memory Barrier}
 DataMemoryBarrier; {Before the First Write}
 
 {Write Register}
 PLongWord(GPIO_REGS_BASE + Reg)^:=(BCM2836_GPCLR_MASK shl Shift);

end;

 


end.
