unit GPIOToggleUnit;

{$mode objfpc}{$H+}

{ Advanced example - Dedicated CPU                                             }
{                                                                              }
{ This file contains the GPIO functionality for our dedicated CPU example.     }
{                                                                              }

interface


uses
 BCM2837,
 GlobalConst,
 GlobalConfig,
 Platform;
  
 
procedure GPIOPinOn(Pin:LongWord);
procedure GPIOPinOff(Pin:LongWord);
function GPIOPinRead(Pin:LongWord):LongWord;
implementation

procedure GPIOPinOn(Pin:LongWord);
var
 Reg:LongWord;
 Shift:LongWord;
 
begin
 {Get Shift}
 Shift:=Pin mod 32;

 {Get Register}
 Reg:=BCM2837_GPSET0 + ((Pin div 32) * SizeOf(LongWord));
 
 {Memory Barrier}
 DataMemoryBarrier; {Before the First Write}
 
 {Write Register}
 PLongWord(GPIO_REGS_BASE + Reg)^:=(BCM2837_GPSET_MASK shl Shift);

end;

procedure GPIOPinOff(Pin:LongWord);
var
 Reg:LongWord;
 Shift:LongWord;
 
begin
 {Get Shift}
 Shift:=Pin mod 32;

 {Get Register}
 Reg:=BCM2837_GPCLR0 + ((Pin div 32) * SizeOf(LongWord));
 
 {Memory Barrier}
 DataMemoryBarrier; {Before the First Write}
 
 {Write Register}
 PLongWord(GPIO_REGS_BASE + Reg)^:=(BCM2837_GPCLR_MASK shl Shift);

end;

function GPIOPinRead(Pin:LongWord):LongWord;
var
 Reg:LongWord;
 Shift:LongWord;
 
begin
 {Get Shift}
 Shift:=Pin mod 32;
 
 {Get Register}
 Reg:=BCM2837_GPLEV0 + ((Pin div 32) * SizeOf(LongWord));
 
 {Read Register}
 Result:=(PLongWord(GPIO_REGS_BASE + Reg)^ shr Shift) and BCM2837_GPLEV_MASK;

 {Memory Barrier}
 DataMemoryBarrier; {After the Last Read}
 
end;
 


end.
