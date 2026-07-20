unit Horse.Proc;

{$IF DEFINED(FPC)}
  {$MODE DELPHI}{$H+}
{$ENDIF}

interface

{$IF NOT DEFINED(FPC)}
uses
  System.SysUtils;
{$ENDIF}

type
  TProc = {$IF DEFINED(FPC)}{$IF DEFINED(HORSE_FPC_FUNCTIONREFERENCES)}reference to {$ENDIF}procedure{$ELSE}System.SysUtils.TProc{$ENDIF};
  // Sob FPC com funcref, TNextProc e TProc precisam ser o MESMO tipo (alias),
  // como acontece no Delphi (ambos = System.SysUtils.TProc). Tipos "reference to
  // procedure" declarados separadamente sao distintos no FPC, o que quebraria a
  // atribuicao de handlers "procedure(...; Next: TProc)" a THorseCallback.
  TNextProc = {$IF DEFINED(FPC)}{$IF DEFINED(HORSE_FPC_FUNCTIONREFERENCES)}TProc{$ELSE}procedure of object{$ENDIF}{$ELSE}System.SysUtils.TProc{$ENDIF};

{$IF DEFINED(FPC)}
  TProc<T> = {$IF DEFINED(HORSE_FPC_FUNCTIONREFERENCES)}reference to {$ENDIF}procedure(Arg1: T);
{$ENDIF}

implementation

end.
