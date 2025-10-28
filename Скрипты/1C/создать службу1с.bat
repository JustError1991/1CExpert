@echo off
rem Примечание : Для удаления сервиса - закомментировать последнюю строку
rem Примечание : Кодировка данного файла должна быть 866 (OEM)
rem Пользователь от имени которого запускается 1С сервер
set SrvUserName=Name
rem Пароль пользователя от имени которого запускается 1С сервер
rem Можно указать любой пароль, а в последствии изменить его в services.msc
set SrvUserPwd=Password
rem TCP порты на которых будет работать 1С сервер.
rem Для дополнительных серверов традиционные значения 2560:2591,2541,2540; 3560:3591,3541,3540: 4560:4591,4541,4540 итд.
set RangePort=1560:1591
set BasePort=1541
set CtrlPort=1540
rem Версия платформы в формате 8.X.YY.ZZZZ
set vers=8.3.26.1581
rem Название сервиса, как оно будет выглядеть в services.msc
set SrvcName="Agent server 1C 8.3 (x86-64) %CtrlPort%"
rem Далее можно ничего не изменять.
set ClusterRegPath=E:\srvinfo_%BasePort%
set BinPath="\"C:\Program Files\1cv8\%vers%\bin\ragent.exe\" -srvc -agent -regport %BasePort% -port %CtrlPort% -range %RangePort% -d \"%ClusterRegPath%\" -debug"
set Desctiption="Agent server 1C. Parameters: %vers% (%CtrlPort%)"
if not exist "%ClusterRegPath%" (
    mkdir "%ClusterRegPath%"
    echo Не забудьте предоставить права на запись в %ClusterRegPath% пользователю %SrvUserName%
    pause
)
sc stop %SrvcName%
sc delete %SrvcName%
sc create %SrvcName% binPath=%BinPath% start=auto obj=%SrvUserName% password=%SrvUserPwd% displayname=%Desctiption% depend=Tcpip/Dnscache/lanmanworkstation/lanmanserver/