unit ThreadUnit_GPS;

{$mode objfpc}{$H+}

{ Advanced example - Dedicated CPU                                             }
{                                                                              }
{ This file contains the main functionality for our dedicated CPU example.     }
{                                                                              }

interface

uses
  GlobalConfig,
  GlobalConst,
  GlobalTypes,
  Platform,
  Threads,
  SysUtils,
  BCM2836,
  {GPIOToggleUnit,}
  Console;   {Include the console unit so we can output logging to the screen}

  
{The start function which does all the setup work for our dedicated thread}
procedure StartDedicatedThreadGPS(Handle:TWindowHandle);


implementation


var
 Countergps:LongWord;
 RightWindow:TWindowHandle;
 

{Forward declaration of our dedicated CPU thread function}
function DedicatedThreadExecutegps(Parameter:Pointer):PtrInt; forward;
 

{This is the startup function which creates the dedicated CPU thread and handles all of
 the setup work to migrate other threads away from the selected CPU. The comments contain
 a lot of important information, make sure you read them well}
procedure StartDedicatedThreadGPS(Handle:TWindowHandle);
var
 Lastgps:LongWord;
 Countgps:Integer;
 Messagegps:TMessage;
 CurrentCPUgps:LongWord;
 DedicatedThreadgps:TThreadHandle;
 ThreadCurrentgps:PThreadSnapshot;
 ThreadSnapshotgps:PThreadSnapshot;
 
begin
 {Because parts of Ultibo core like the file system and network start in asynchronous mode
  we'll stop here for a second just to make sure they are done. You've seen in other examples
  how to wait for the network to have a valid IP and how to wait for drive C:\ to be ready, 
  to keep this example simple we'll just sleep for three seconds which should be enough for now}
 Sleep(3000);
  
  
 {Create another console window so we can track the progress of our thread later}
 RightWindow:=ConsoleWindowCreate(ConsoleDeviceGetDefault,CONSOLE_POSITION_TOPRIGHT,False);
 
 
 {Some initial housekeeping just to be safe, check the number of CPUs available}
 if CPUGetCount < 4 then
  begin
   {Less than 4 is bad, we can't continue with the example}
   ConsoleWindowWriteLn(Handle,'Error, less than 4 CPUs available');
   Exit;
  end;
 ConsoleWindowWriteLn(Handle,'CPU Countgps is ' + IntToStr(CPUGetCount));
 
 
 {First step is to create a new thread and assign it to the CPU that we want to take
  over, this is just the same as creating any other thread except we want to explicitly
  set the CPU for it to run on and also the affinity so that it cannot run on any other CPU. 
  
  We can do this in one step by calling the SysBeginThreadEx() function but we can also do it
  by using the normal BeginThread() function and then adjusting the CPU and affinity later}
 DedicatedThreadgps:=BeginThread(@DedicatedThreadExecutegps,nil,DedicatedThreadgps,THREAD_STACK_DEFAULT_SIZE);
 ConsoleWindowWriteLn(Handle,'Created dedicated CPU thread with handle ' + IntToHex(DedicatedThreadgps,8));
 
 
 {Let's set the name of our thread so we can see it in the thread list}
 ThreadSetName(DedicatedThreadgps,'Dedicated CPU Thread GPS');
 ConsoleWindowWriteLn(Handle,'Set name of thread to "Dedicated CPU Thread GPS"');
 
 
 {Now we can set the affinity of our thread to CPU 2 and wait for the scheduler to migrate it for us}
 ThreadSetAffinity(DedicatedThreadgps,CPU_AFFINITY_2);
 ConsoleWindowWriteLn(Handle,'Set affinity of dedicated CPU thread to ' + CPUIDToString(CPU_ID_2));
 
 
 {Migrations happen during context switches, so our thread may not be instantly on the new CPU, instead
  we check where our thread is and wait for it to migrate if needed}
 CurrentCPUgps:=ThreadGetCPU(DedicatedThreadgps);
 if CurrentCPUgps <> CPU_ID_2 then
  begin
   ConsoleWindowWriteLn(Handle,'Thread ' + IntToHex(DedicatedThreadgps,8) + ' currently on ' + CPUIDToString(CurrentCPUgps));
   
   {Keep checking until it is migrated}
   while ThreadGetCPU(DedicatedThreadgps) <> CPU_ID_2 do
    begin
     Sleep(1000);
    end;
  end;
 ConsoleWindowWriteLn(Handle,'Thread ' + IntToHex(DedicatedThreadgps,8) + ' now on ' + CPUIDToString(ThreadGetCPU(DedicatedThreadgps)));
 
 
 {Now we disable thread migrations temporarily so that we don't have threads moving around while we
  are trying to setup our dedicated CPU, you can see this on the "Scheduler" page in web status}
 SchedulerMigrationDisable;
 ConsoleWindowWriteLn(Handle,'Disabled scheduler migration');
 
 
 {We also don't want any more threads created on our dedicated CPU so we need to disable thread 
  allocation as well but only for that CPU and not the others, if you look in the InitUnit you
  will also see this function being called during initialization. As part of understanding how 
  this process works you should try commenting that out and see the difference when you run the 
  example again}
 SchedulerAllocationDisable(CPU_ID_2);
 ConsoleWindowWriteLn(Handle,'Disabled scheduler allocation for ' + CPUIDToString(CPU_ID_2));
 ConsoleWindowWriteLn(Handle,'Now using asm language on RPi2 to toggle gpio ');
 
 
 {Our final step in the process is to migrate all of the other threads away from our dedicated CPU
  so they are able to continue running without any impact. To do this we need to know what threads
  are running on CPU 3, we can use the ThreadSnapshotCreate() function to get a current list}
 
 {We also want to Countgps how many threads need to be migrated so we'll start with zero}
 Countgps:=0; 
 
 
 {Then create a thread snapshot, the snapshot contains all of the thread information at a precise 
  point in time. The real thread information changes hundreds of times per second and so isn't easy
  to read directly}
 ThreadSnapshotgps:=ThreadSnapshotCreate;
 if ThreadSnapshotgps <> nil then
  begin
  
   {Get the first thread in the snapshot}
   ThreadCurrentgps:=ThreadSnapshotgps;
   while ThreadCurrentgps <> nil do
    begin
    
     {Check the handle of the thread to make sure it is not our dedicated CPU thread}
     if ThreadCurrentgps^.Handle <> DedicatedThreadgps then
      begin
      
       {Check the CPU to see if it is on CPU 3}
       if ThreadCurrentgps^.CPU = CPU_ID_2 then
        begin
        
         {In our normal configuration there are 4 threads on each CPU that we cannot migrate because
          they form a special part of the internals of Ultibo core and are needed for the system to
          function. That doesn't mean we can't have a dedicated CPU just for our purpose because at 
          least 3 of these threads never run and the fourth one is the idle thread which does nothing
          except run when no one else is ready.
          
          So what are these special threads?
          
           1. The Idle thread, this just runs when no other threads are ready. It also counts CPU 
              utilization so if it doesn't run then our CPU may appear to be 100% in use but that
              is fine because we want to use it for just one purpose anyway.
              
           2. The IRQ thread, on CPU 0 this is actually the thread that started the system in most
              cases but after that it never runs again, on the other CPUs it is the thread that was
              used to start the CPU and again it will never run after that. If you look at the thread
              list in web status you will see the IRQ threads (one for each CPU) are shown as priority
              THREAD_PRIORITY_NONE which means that they are placed on a special thread queue that the
              scheduler never chooses from. The threads are still ready to run but will never be given
              the chance.
              
           3 and 4. The FIQ and SWI threads, these 2 along with the IRQ threads also have a very important 
              role to play in managing the internal operation of Ultibo core. Even though they will never
              run (because they are THREAD_PRIORITY_NONE) their thread handle is used whenever the system
              is executing an interrupt. So when an IRQ is occurring the system will use the handle of the
              IRQ thread, likewise when an FIQ or fast interrupt is occurring the system will use the handle
              of the FIQ thread. In the same way the system uses the SWI thread to perform software interrupts}
         
         {Check for one of the special threads and if it is not then ask it to migrate}
         if ThreadCurrentgps^.Handle = SchedulerGetThreadHandle(CPU_ID_2,THREAD_TYPE_IDLE) then
          begin
          
           {This is the idle thread, we can't migrate this one}
           ConsoleWindowWriteLn(Handle,'Skipping migration of idle thread "' + ThreadGetName(ThreadCurrentgps^.Handle) + '"');
          end
         else if ThreadCurrentgps^.Handle = SchedulerGetThreadHandle(CPU_ID_2,THREAD_TYPE_IRQ) then  
          begin
          
           {This one is the IRQ thread and it can't be migrated either}
           ConsoleWindowWriteLn(Handle,'Skipping migration of IRQ thread "' + ThreadGetName(ThreadCurrentgps^.Handle) + '"');
          end
         else if ThreadCurrentgps^.Handle = SchedulerGetThreadHandle(CPU_ID_2,THREAD_TYPE_FIQ) then  
          begin
          
           {FIQ threads also can't be migrated but they never run so it doesn't matter}
           ConsoleWindowWriteLn(Handle,'Skipping migration of FIQ thread "' + ThreadGetName(ThreadCurrentgps^.Handle) + '"');
          end
         else if ThreadCurrentgps^.Handle = SchedulerGetThreadHandle(CPU_ID_2,THREAD_TYPE_SWI) then    
          begin
          
           {And the SWI threads are the same so we can ignore them as well}
           ConsoleWindowWriteLn(Handle,'Skipping migration of SWI thread "' + ThreadGetName(ThreadCurrentgps^.Handle) + '"');
          end
         else
          begin
          
           {If the thread is not any of those then it must be a normal thread. Ask the scheduler to migrate it
            to CPU 0 instead, we could specify any CPU and we could try to round robin them but the scheduler 
            will rebalance anyway once we enable migrations again}
           ThreadSetCPU(ThreadCurrentgps^.Handle,CPU_ID_0);
           ConsoleWindowWriteLn(Handle,'Migrating thread "' + ThreadGetName(ThreadCurrentgps^.Handle) + '" to ' + CPUIDToString(CPU_ID_0));
           
           {Add one to our migrated thread Countgps}
           Inc(Countgps);
          end;          
        end; 
      end
     else
      begin
      
       {No need to migrate our own thread, that wouldn't make any sense!}
       ConsoleWindowWriteLn(Handle,'Skipping migration for "' + ThreadGetName(ThreadCurrentgps^.Handle) + '"');
      end;
     
     {Get the next thread from the snapshot}
     ThreadCurrentgps:=ThreadCurrentgps^.Next;
    end; 
   
   {Remember to destroy the snapshot when we have finished using it}
   ThreadSnapshotDestroy(ThreadSnapshotgps);
  end; 
  
 {Print the number of threads that we asked to migrate}
 ConsoleWindowWriteLn(Handle,'Migrated ' + IntToStr(Countgps) +  ' threads from ' + CPUIDToString(CPU_ID_2));
 
 {As we saw above, thread migrations happen during context switches. So even though we asked each of 
  the threads above to migrate they may not neccessarily have done that if they haven't performed a
  context switch since our request. There are many reasons why a thread might not perform a context
  switch, the main reason is if the thread is not ready to run because it is waiting or sleeping.
  
  Let's sleep for a second and then quickly run through a new snapshot to check if everyone has migrated}
 Sleep(1000);
 
 {Create the snapshot and reset the Countgps}
 Countgps:=0;
 ThreadSnapshotgps:=ThreadSnapshotCreate;
 if ThreadSnapshotgps <> nil then
  begin
   {Get the first thread}
   ThreadCurrentgps:=ThreadSnapshotgps;
   while ThreadCurrentgps <> nil do
    begin
     {Check the handle and the CPU}
     if (ThreadCurrentgps^.Handle <> DedicatedThreadgps) and (ThreadCurrentgps^.CPU = CPU_ID_2) then
      begin
       if (ThreadCurrentgps^.Handle <> SchedulerGetThreadHandle(CPU_ID_2,THREAD_TYPE_IDLE))
        and (ThreadCurrentgps^.Handle <> SchedulerGetThreadHandle(CPU_ID_2,THREAD_TYPE_IRQ))
        and (ThreadCurrentgps^.Handle <> SchedulerGetThreadHandle(CPU_ID_2,THREAD_TYPE_FIQ))
        and (ThreadCurrentgps^.Handle <> SchedulerGetThreadHandle(CPU_ID_2,THREAD_TYPE_SWI)) then
        begin
         {Add one to our Countgps}
         Inc(Countgps);
        end;
      end;
      
     {Get the next thread}
     ThreadCurrentgps:=ThreadCurrentgps^.Next;
    end;
    
   {Destroy the snapshot}
   ThreadSnapshotDestroy(ThreadSnapshotgps);
  end;

  
 {Check the Countgps to see if any threads have not migrated yet, we won't proceed if there are any.
 
  If you are trying the example with the line from the InitUnit commented out, then take a look at
  the "Thread List" to see which threads did not migrate even though we asked them to. 
  
  Can you see why they didn't migrate?}
 if Countgps <> 0 then
  begin
   ConsoleWindowWriteLn(Handle,'Error, ' + IntToStr(Countgps) +  ' threads remaining on ' + CPUIDToString(CPU_ID_2));
   Exit;
  end;
 ConsoleWindowWriteLn(Handle,'No threads remaining on ' + CPUIDToString(CPU_ID_2) + ' proceeding with example');
 
 
 {Send a message to our dedicated CPU thread to tell it we are done and it can go ahead}
 FillChar(Messagegps,SizeOf(TMessage),0);
 ThreadSendMessage(DedicatedThreadgps,Messagegps);
 ConsoleWindowWriteLn(Handle,'Sent a Messagegps to the dedicated CPU thread');
 
 
 {Enable thread migrations now that we are all done, the scheduler will not touch our dedicated CPU}
 SchedulerMigrationEnable;
 ConsoleWindowWriteLn(Handle,'Enabled scheduler migration');
 
 
 {Because our dedicated CPU thread won't be able to print on the console, we'll go into a loop here
  and print the value of the Countergps variable that it is incrementing. That way you can see just how 
  many loops it can do in a second}
 Lastgps:=0;
 while True do
  begin
   {Check if anything has happened}
   if Lastgps <> Countergps then
    begin
     {Print the Countergps value on the right window}
     ConsoleWindowWriteLn(RightWindow,'Countergps value is ' + IntToStr(Countergps) + ', Difference is ' + IntToStr(Countergps - Lastgps));
    end;
   Lastgps:=Countergps; 
   
   {Wait one second}
   Sleep(1000);
  end;  
end;


{This is the thread function for our dedicated CPU thread, to use this technique
 you need to understand the rules about what you can and can't do when taking over
 a CPU for real time use. Again the comments in this function explain many of the
 things you need to know so read them carefully before using this in your own programs} 
function DedicatedThreadExecutegps(Parameter:Pointer):PtrInt;
var
 StartCountgps:Int64;
 CurrentCountgps:Int64;
 Messagegps:TMessage;
begin

 Result:=0;
 //GPIOFunctionSelect(GPIO_PIN_16,GPIO_FUNCTION_OUT);
 {Do a loop while we are not on our dedicated CPU}
 ConsoleWindowWriteLn(RightWindow,'Waiting for migration to ' + CPUIDToString(CPU_ID_2));
 while ThreadGetCPU(ThreadGetCurrent) <> CPU_ID_2 do
  begin
   Sleep(1000);
  end;
 
 
 {Wait for a Messagegps from the main thread to say we are ready to go}
 ConsoleWindowWriteLn(RightWindow,'Waiting for a Messagegps from the main thread');
 ThreadReceiveMessage(Messagegps);
 ConsoleWindowWriteLn(RightWindow,'Received a Messagegps, taking control of CPU');
 
 
 {Now that we are in control, let's disable preemption so the scheduler won't
  interrupt us at all, once we do this we can no longer call any function that
  will cause our thread to sleep or yield since without preemption the scheduler
  will not be able to switch back to our thread}
 ConsoleWindowWriteLn(RightWindow,'Disabling scheduler preemption on ' + CPUIDToString(CPU_ID_2));
 SchedulerPreemptDisable(CPU_ID_2);
  
  
 {Go into our loop doing whatever we want, no one else is here so we can break all the rules!
 
  Now that preemption is disabled the scheduler interrupts will still occur but the scheduler
  will not switch away from our thread. If you look at the "CPU" page in web status while this
  is happening you will see the CPU utilization runs at 100% for CPU 3}
 Countergps:=0;
 StartCountgps:=GetTickCount64;
 while True do
  begin
   {Increment our loop Countergps}
   Inc(Countergps);
   
   {See how much time has elapsed since we started the loop, 30,000 milliseconds (or 30 seconds)
    should be enough time for you to see what is happening but you can extend it if you like}
   CurrentCountgps:=GetTickCount64;
   if CurrentCountgps > (StartCountgps + 5000) then Break;
   
   {There's no need to sleep on each loop, this is our CPU and no one can tell us what to do.
   
    More importantly we must NOT sleep because that would switch to the idle thread and never
    return to here again}
  end; 
  
 {We can switch back and forth between dedicated and standard mode which can be useful to allow
  using other functions that cannot be called while preemption is disabled. Let's reenable the
  scheduler preemption and then print something on the console}
 SchedulerPreemptEnable(CPU_ID_2);
 ConsoleWindowWriteLn(RightWindow,'Enabled scheduler preemption on ' + CPUIDToString(CPU_ID_2));

 
 {With preemption disabled the scheduler interrupts were still occuring, in a realtime scenario
  this could still affect our timing because the interrupts happen every 500 microseconds. This
  time let's disable interrupts completely so the only thing happening on the CPU is our thread.
  
  Remember once we disable interrupts any call to a function that tries to sleep, yield, wait or
  acquire a lock will most likely deadlock the CPU and never ever ever return!
  
  Do you think you understood that? Read it again just to be sure!}
 ConsoleWindowWriteLn(RightWindow,'Disabling interrupts and fast interrupts on ' + CPUIDToString(CPU_ID_2));
 DisableFIQ;
 DisableIRQ;

 {Of course you can reenable interrupts when you need to do something like allocate some memory
  or read or write to a file. There are a number of choices available, the simplest is just to
  call EnableFIQ and EnableIRQ which will undo the disable from above.
  
  Ultibo also has a several pairs of functions that allow you to recursively disable and enable
  interrupts without having to count how many times you disabled and then reenable using the same
  number of calls. The SaveIRQFIQ function disables both IRQ and FIQ and then returns a mask to
  indicate the previous state, when you want to enable again you just pass the mask back to the
  RestoreIRQFIQ function which will only actually reenable if interrupts were previously enabled.
  
  Got that, maybe not but it will make more sense when you need to use it!}
 
 {Go back to looping and counting, the main thread is still watching so it will continue printing
  the Countergps values while we do this as well}
 StartCountgps:=GetTickCount64;
 while True do
  begin
   {Increment our loop Countergps}
   Inc(Countergps);

   {Check our tick count for elapsed time}
   CurrentCountgps:=GetTickCount64;
   if CurrentCountgps > (StartCountgps + 5000) then Break;
   
   {No sleeping here, this is a realtime only thread. Seriously you cannot sleep in this scenario, go
    on try it if you don't believe me and see what happens}
  end;

  ConsoleWindowWriteLn(RightWindow,'Starting asm  toggle ');
 {That's the end of the example and now you can explore on your own
 
  Remember, in the dedicated CPU scenario there are very strict rules about what functions you can
  call in Ultibo core.
  
  Pretty much any function that allocates memory is out of the question because the memory manager 
  uses locks, without memory then most functions are off limits so you need to plan your code in 
  advance to allocate any memory you might want beforehand or to switch in and out of dedicated
  mode as required in order to interact with the rest of Ultibo core.
  
  Have fun!}  
 while True do
  begin 
   {Don't think the Countergps values per loop were as high as you expected? Try uncommenting this
    line and see how many loop iterations happen per second with no other code}
   Inc(Countergps);
   //GPIOPinOn(21); 
   //GPIOPinOff(21);
  end;
  
 {If you really want to see just how fast a single CPU can go, try commenting out the loop above
  so that the dedicated thread executes this small piece of inline assembler instead. This loop 
  only contains 3 ARM instructions so it isn't very real world but it does increment and store
  the value of the Countergps as many times as it possibly can per second}
 {$IFDEF CPUARM}  
 asm
  //R0 = Countergps address
  //R1 = Countergps value
  //R2 = GPIO address
  //R3 = GPIO output value

  //Load the Countergps address and value
  ldr r0, .LCountergps
  ldr r1, [r0]

  //Load the GPIO address and value
  ldr r2, =BCM2836_GPIO_REGS_BASE
  mov r3, #0x10000

  .LLoop:
  //Increment and store the Countergps
  add r1, r1, #1
  str r1, [r0]

  //Do a small delay
  mov r4, #30
  .LWait1:
  sub r4, r4, #1
  cmp r4, #0
  bne .LWait1

  //Turn the pin on
  str r3, [r2, #BCM2836_GPSET0]

  //Do a small delay
  mov r4, #30
  .LWait2:
  sub r4, r4, #1
  cmp r4, #0
  bne .LWait2

  //Turn the pin off
  str r3, [r2, #BCM2836_GPCLR0]

  //Repeat the loop
  b .LLoop

  .LCountergps:
  .long   Countergps
 end;
 {$ENDIF CPUARM}   
end;


end.
