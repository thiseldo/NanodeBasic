5 REM PWM.BAS - demo of PWM output
10 FOR A=0 TO 255
20 AOUT 6=A
30 SLEEP 10
40 NEXT A
50 FOR B=255 TO 0 STEP -1
60 AOUT 6=B
70 SLEEP 10
80 NEXT B
