unit Horse.WebModule;

{$IF DEFINED(FPC)}
  {$MODE DELPHI}{$H+}
{$ENDIF}

interface

uses
{$IF DEFINED(FPC)}
  Classes,
  httpdefs,
  fpHTTP,
  fpWeb,
{$ELSE}
  System.Classes,
  Web.HTTPApp,
{$ENDIF}
  Horse.Core;

{ PATCH-CSRF-1 — guard de feature por versão do FPC (automático; NÃO exige define do projeto).
  `TCustomFPWebModule.IsWriteRequest` existe apenas no fcl-web do FPC trunk (3.3.x+), onde
  entrou junto com um cheque de token CSRF que quebra POST em providers FPC baseados
  em THorseWebModule (ver
  detalhe na declaração do método). Em FPC 3.2.x o método NÃO existe (e o bug tampouco),
  então o `override` é desnecessário e QUEBRARIA a compilação. A detecção usa a fronteira
  real de versão: FPC 3.2.x = 302xx (< 30300); 3.3.x/trunk = 30301+ (>= 30300).
  Escape hatch OPCIONAL (não necessário no uso normal): definir `HORSE_FPC_NO_IS_WRITE_REQUEST`
  desliga o override — só útil no caso raro de um snapshot de trunk 3.3.x ANTERIOR à
  introdução do método (que a checagem de versão não distingue). }
{$IF DEFINED(FPC)}
  {$IF FPC_FULLVERSION >= 30300}
    {$DEFINE HORSE_FPC_HAS_IS_WRITE_REQUEST}
  {$ENDIF}
  {$IF DEFINED(HORSE_FPC_NO_IS_WRITE_REQUEST)}
    {$UNDEF HORSE_FPC_HAS_IS_WRITE_REQUEST}
  {$ENDIF}
{$ENDIF}

type
{$IF DEFINED(FPC)}
  THorseWebModule = class(TFPWebModule)
    procedure DoOnRequest(ARequest: TRequest; AResponse: TResponse; var AHandled: Boolean); override;
    {$IFDEF HORSE_FPC_HAS_IS_WRITE_REQUEST}
    { PATCH-CSRF-1 — override do cheque CSRF de escrita do fcl-web.
      O FPC trunk introduziu em TCustomFPWebModule.HandleRequest (fpweb.pp) um cheque
      de token CSRF que, para métodos de escrita (POST/PUT/DELETE/PATCH/BATCH), acessa
      Session ANTES de DoOnRequest. Como o Horse não habilita CreateSession e não seta
      FSessionRequest neste caminho, o getter Session lança
      "Default session not available outside handlerequest", quebrando toda rota de
      escrita em providers FPC baseados em THorseWebModule. O Horse faz
      seu próprio roteamento e não usa o token CSRF de sessão do fcl-web; retornar False
      faz o teste dar short-circuit sem tocar Session, sem criar sessão/cookie.
      Compilado só quando o método existe (ver guard de versão acima). }
    class function IsWriteRequest(const aMethod: string): Boolean; override;
    {$ENDIF}
{$ELSE}
  THorseWebModule = class(TWebModule)
{$ENDIF}
    procedure HandlerAction(const Sender: TObject; const Request: {$IF DEFINED(FPC)}TRequest{$ELSE}TWebRequest{$ENDIF}; const Response: {$IF DEFINED(FPC)}TResponse{$ELSE}TWebResponse{$ENDIF}; var Handled: Boolean);
  private
    FHorse: THorseCore;
    class var FInstance: THorseWebModule;
  public
    property Horse: THorseCore read FHorse write FHorse;
    constructor Create(AOwner: TComponent); override;
    class function GetInstance: THorseWebModule;
  end;

var
{$IF DEFINED(FPC)}
  HorseWebModule: THorseWebModule;
{$ELSE}
  WebModuleClass: TComponentClass = THorseWebModule;
{$ENDIF}

implementation

uses

{$IF DEFINED(FPC)}
  SysUtils,
{$ELSE}
  System.SysUtils,
{$ENDIF}        
  Horse.Request,
  Horse.Response,
  Horse.Exception.Interrupted;

{$IF DEFINED(FPC)}
  {$R Horse.WebModule.lfm}
{$ELSE}
  {$R *.dfm}
{$ENDIF}

class function THorseWebModule.GetInstance: THorseWebModule;
begin
  Result := FInstance;
end;

constructor THorseWebModule.Create(AOwner: TComponent);
begin
  {$IF DEFINED(FPC)}
  inherited CreateNew(AOwner, 0);
  {$ELSE}
  inherited;
  {$ENDIF}
  FHorse := THorseCore.GetInstance;
  FInstance := Self;
end;

{$IF DEFINED(FPC)}
procedure THorseWebModule.DoOnRequest(ARequest: {$IF DEFINED(FPC)}TRequest{$ELSE}  TWebRequest {$ENDIF}; AResponse: {$IF DEFINED(FPC)}TResponse{$ELSE}  TWebResponse {$ENDIF}; var AHandled: Boolean);
begin
  HandlerAction(Self, ARequest, AResponse, AHandled);
end;

{$IFDEF HORSE_FPC_HAS_IS_WRITE_REQUEST}
{ PATCH-CSRF-1 — ver comentário na declaração da classe. O Horse não participa do
  esquema de token CSRF de sessão do fcl-web; tratar todo método como "não-escrita"
  aqui apenas impede o acesso prematuro a Session em TCustomFPWebModule.HandleRequest. }
class function THorseWebModule.IsWriteRequest(const aMethod: string): Boolean;
begin
  Result := False;
end;
{$ENDIF}
{$ENDIF}

procedure THorseWebModule.HandlerAction(const Sender: TObject; const Request: {$IF DEFINED(FPC)}TRequest{$ELSE}TWebRequest{$ENDIF};
  const Response: {$IF DEFINED(FPC)}TResponse{$ELSE}TWebResponse{$ENDIF}; var Handled: Boolean);
var
  LRequest: THorseRequest;
  LResponse: THorseResponse;
begin
  Handled := True;
  LRequest := THorseRequest.Create(Request);
  LResponse := THorseResponse.Create(Response);
  try
    try
      FHorse.Routes.Execute(LRequest, LResponse);
    except
      on E: Exception do
      begin
        if not E.InheritsFrom(EHorseCallbackInterrupted) then
          raise;
      end;
    end;
  finally
    if LRequest.Body<TObject> = LResponse.Content then
      LResponse.Content(nil);
    LRequest.Free;
    LResponse.Free;
  end;
end;

{$IF DEFINED(FPC)}
initialization
  RegisterHTTPModule(THorseWebModule);
{$ENDIF}

end.
