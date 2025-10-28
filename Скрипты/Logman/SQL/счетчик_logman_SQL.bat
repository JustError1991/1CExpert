@echo off
:: Создаем сборщик данных
logman create counter Monitor1C -f bin -si 10 -v mmddhhmm -o "H:\PerfLogs\Monitor1C" -cf "H:\Scripts\Logman\logman1C.txt"
pause 10