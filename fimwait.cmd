%% ==================================================
%% Autor    : Aldrin  Monteiro 
%% Funcao   : Programa para fechar mensagem de espera
%% Programa : Fimwait (fimwait.cmd)
%% Data     : 03/02/94
%% Realizar teste cherry-pick
%%  Ja com o Commit
%% ==================================================

Procedure FimWait()
   if $currentwindow='wwait'
      win close wwait
   endif
EndProcedure
