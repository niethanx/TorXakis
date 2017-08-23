@REM TorXakis - Model Based Testing
@REM Copyright (c) 2015-2017 TNO and Radboud University
@REM See LICENSE at root directory of this repository.

@ECHO OFF
REM where torxakis.bat
SET TORXAKIS=torxakis.bat
SET REL=examps\CustomersOrders
SET EXAMPS=%1\%REL%
SET TEST=%1\test\%REL%

echo ------- Start CustomersOrders Test
echo %DATE%%TIME%
start /min java -cp %EXAMPS% CustomersOrders
call %TORXAKIS% %EXAMPS%\CustomersOrders.txs < %TEST%\CustomersOrders_Tester.txscmd
TIMEOUT /T 2 /NOBREAK
move /Y testTrace.log testTrace.Spec.CustomersOrders.Sut.CustomersOrders.log
echo ------- End CustomersOrders Test
echo %DATE%%TIME%