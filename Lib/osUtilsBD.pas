//*********************************************************************************//
//Unit: osUtilsBD                                                                  //
//Classes:                                                                         //
//  -TAlteradorBD                                                                  //
//*********************************************************************************//

unit osUtilsBD;

interface

uses
  Classes, osSQLDataSet, IdGlobal, SysUtils, variants, DB;

const
  //defini��o das constantes de erro
  E_CAMPO_EXISTENTE = 'O campo j� existe';
  E_CAMPO_INEXISTENTE = 'Campo inexistente';
  E_IMPOSSIVEL_INSERIR_CAMPO = 'Imposs�vel inserir campo';
  E_SEM_CAMPOS = 'N�o existem campos';
  E_TABELA_NAO_DEFINIDA = 'A tabela n�o est� definida';
  E_CHAVE_SEM_VALOR = 'Existe uma chave sem um valor definido';

type
  //tipo utilizado para definir as propriedades de um campo
  TPropsCampo = class
    public
      Tipo: TFieldType;
      SubTipo: TFieldType;
      Chave: Boolean;
      Valor: Variant;
  end;
  //defini��o da classe TAlteradorBD
  TAlteradorBD = class
  private
    FnomesCampos: TStringList;       //os nomes de todos os campos envolvidos
    FNomeTabela: string;             //o nome da tabela que est� sendo atualizada

    property nomesCampos: TStringList read FnomesCampos write FnomesCampos;

    function getSelect: string;
    function getFrom: string;
    function getWhere: string;
    function getInsert: string;
    function getUpdate: string;
    procedure preencheParams(query: TosSQLDataSet);
    procedure inserirRegistro;
    procedure atualizarRegistro;
  public
    property nomeTabela: string read FNomeTabela write FNomeTabela;  //o nome da tabela publicado
    constructor create;
    destructor destroy; override;
    function existeRegistro: boolean;
    procedure inserir(sobreescrever: boolean = false);
    procedure adicionarCampo(PNome: string; PTipo: TFieldType; chave: boolean = false);
    procedure adicionarCampoValor(PNome: string; PTipo: TFieldType; PValor: variant;
      PChave: boolean = false);
    procedure setarSubTipo(PNome: string; PSubTipo: TBlobType);
    procedure setarValor(PNome: string; PValor: variant);
  end;

implementation

uses SQLMainData, SqlExpr;

{ TAlteradorBD }
//**********************************************************************************//
//Classe: TAlteradorBD                                                              //
//Descri��o: A id�ia geral desta classe � evitar que se escreva muitas senten�as    //
//  SQL simples. Assim, baseando-se em tr�s listas a classe deve controlar inser��es//
//  e atualiza��es no banco de dados. Esta classe depende do SQLMainData para       //
//  funcionar. Existem tr�s listas:                                                 //
//      1) nomesCampos: lista de nomes de todos os campos de uma tabela que         //
//                      interessam para a atualiza��o que est� sendo feita          //
//      2) nomesChaves: lista de nomes de todos os campos da lista de campos que    //
//                      dever�o ser tratados como chave                             //
//      3) valoresCampos: lista paralela � lista de nomes de campos que diz respeito//
//                        aos valores correspondentes aos campos                    //
//  Al�m das listas, existe uma propriedade (nomeTabela) que representa o nome da   //
//    tabela que est� sendo atualizada pelo objeto.                                 //
//  Existem 3 m�todos p�blicos al�m do construtor e do destrutor:                   //
//      1) existeRegistro: baseado nas informa��es contidas nas listas, verifica se //
//                         j� existe um registro correspondente (no que diz respeito//
//                         �s chaves) no BD.                                        //
//      2) inserir: insere o registro no BD. Caso o registro j� exista no BD e a    //
//                  propriedade sobreescrever esteja setada para true, gera um      //
//                  update para a tabela.                                           //
//      3) adicionarCampo: � o meio com que os campos s�o adicionados ao objeto     //
//**********************************************************************************//


//*********************************************************************************//
//M�todo: adicionarCampo                                                           //
//Descri��o: Serve para adicionar um campo � lista de campos. O usu�rio da classe  //
//  n�o ter� acesso � lista de nomes dos campos, ficando a cargo deste             //
//  procedimento controlar a liata                                                 //
//*********************************************************************************//
procedure TAlteradorBD.adicionarCampo(PNome: string; PTipo: TFieldType; chave: boolean);
begin
  adicionarCampoValor(PNome, PTipo, NULL, chave);
end;

procedure TAlteradorBD.adicionarCampoValor(PNome: string; PTipo: TFieldType; PValor:variant;
  PChave: boolean);
var
  indiceCampo: integer;
begin
  //se o campo j� existe, retorna um erro
  if (nomesCampos.IndexOf(PNome)<>-1) then
    raise exception.create(E_CAMPO_EXISTENTE);

  //insere o nome do campo na lista de nomes
  indiceCampo := nomesCampos.Add(PNome);

  //criar um objeto setar as propriedades do campo
  nomesCampos.Objects[indiceCampo] := TPropsCampo.Create;
  with TPropsCampo(nomesCampos.Objects[indiceCampo]) do
  begin
    Chave   := PChave;
    Valor   := PValor;
    Tipo    := PTipo;
    SubTipo := ftUnknown;
  end;
end;

//*********************************************************************************//
//M�todo: atualizarRegistro                                                        //
//Descri��o: Envia a senten�a de update para o BDi                                 //
//*********************************************************************************//
procedure TAlteradorBD.atualizarRegistro;
var
  query: TosSQLDataSet;
begin
  query := TosSQLDataSet.Create(nil);
  try
    query.SQLConnection := MainData.SQLConnection;
    query.CommandText := getUpdate + getWhere;
    preencheParams(query);
    query.ExecSQL;
  finally
    freeAndNil(query);
  end;
end;

//*********************************************************************************//
//M�todo: constructor                                                              //
//Descri��o: Construtora da classe. Cria as listas que devem ser criadas.          //
//*********************************************************************************//
constructor TAlteradorBD.create;
begin
  nomesCampos := TStringList.Create;
end;

//*********************************************************************************//
//M�todo: destroy                                                                  //
//Descri��o: Destrutora da classe. Libera as listas que foram criadas na           //
//           construtora.                                                          //
//*********************************************************************************//
destructor TAlteradorBD.destroy;
begin
  nomesCampos.Free;
end;

//*********************************************************************************//
//M�todo: existeRegistro                                                           //
//Descri��o: Verifica a exist�ncia do registro no BD.                              //
//*********************************************************************************//
function TAlteradorBD.existeRegistro: boolean;
var
  query: TosSQLDataSet;
begin
  query := TosSQLDataSet.Create(nil);
  try
    query.SQLConnection := MainData.SQLConnection;
    query.CommandText := 'Select count(1) ' + getFrom + getWhere;
    preencheParams(query);
    query.Open;
    result := query.fields[0].Value>0;
  finally
    freeAndNil(query);
  end;
end;

//*********************************************************************************//
//M�todo: getFrom                                                                  //
//Descri��o: Gera uma parte de c�digo SQL referente ao FROM.                       //
//*********************************************************************************//
function TAlteradorBD.getFrom: string;
begin
  if nomeTabela='' then
    raise Exception.Create(E_TABELA_NAO_DEFINIDA);
  result := ' FROM ' + FNomeTabela + ' ';
end;

//*********************************************************************************//
//M�todo: getInsert                                                                //
//Descri��o: Gera a parte do insert do c�digo SQL j� com o INTO e values. Os       //
//           valores s�o parametrizados.                                           //
//*********************************************************************************//
function TAlteradorBD.getInsert: string;
var
  sent: string;
  i: integer;
begin

  if nomeTabela='' then
    raise Exception.Create(E_TABELA_NAO_DEFINIDA);

  sent := 'INSERT INTO ' + FNomeTabela + ' ';

  sent := sent + '(';
  for i := 0 to nomesCampos.Count-1 do
  begin
    sent := sent + nomesCampos[i];
    if i<nomesCampos.Count-1 then
      sent := sent + ', ';
  end;
  sent := sent + ') values (';

  for i := 0 to nomesCampos.Count-1 do
  begin
    sent := sent + ':'+nomesCampos[i];
    if i<nomesCampos.Count-1 then
      sent := sent + ', ';
  end;
  Result := sent + ') ';
end;

//*********************************************************************************//
//M�todo: getSelect                                                                //
//Descri��o: Gera a parte de c�digo SQL referente a um SELECT                      //
//*********************************************************************************//
function TAlteradorBD.getSelect: string;
var
  sent: string;
  i: integer;
begin
  sent := 'SELECT ';
  for i := 0 to nomesCampos.Count-1 do
  begin
    sent := sent + nomesCampos[i];
    if i<nomesCampos.Count-1 then
      sent := sent + ', ';
  end;
  result := sent + ' ';
end;

//*********************************************************************************//
//M�todo: getUpdate                                                                //
//Descri��o: Gera a parte de c�digo SQL referente a um UPDATE j� com SET. Os       //
//           valores v�o parametrizados.                                           //
//*********************************************************************************//
function TAlteradorBD.getUpdate: string;
var
  sent: string;
  i: integer;
begin

  if nomeTabela='' then
    raise Exception.Create(E_TABELA_NAO_DEFINIDA);

  sent := 'UPDATE ' + FNomeTabela + ' SET ';

  for i := 0 to nomesCampos.Count-1 do
  begin
    sent := sent + nomesCampos[i] + '= :' + nomesCampos[i];
    if i<nomesCampos.Count-1 then
      sent := sent + ', ';
  end;
  Result := sent + ' ';
end;

//*********************************************************************************//
//M�todo: getUpdate                                                                //
//Descri��o: Gera a parte de c�digo SQL referente a um WHERE j� com ANDs. Os       //
//           valores v�o parametrizados. Somente campos chave s�o inseridos        //
//*********************************************************************************//
function TAlteradorBD.getWhere: string;
var
  sent: string;
  i: integer;
begin
  sent := ' WHERE ';
  for i := 0 to nomesCampos.Count-1 do
  begin
    if TPropsCampo(nomesCampos.Objects[i]).Chave then
      sent := sent + nomesCampos[i] + '= :' + nomesCampos[i];
  end;
  result := Copy(sent, 0, length(sent)-4);
end;

//*********************************************************************************//
//M�todo: inserir                                                                  //
//Descri��o: J� descrito.                                                          //
//*********************************************************************************//
procedure TAlteradorBD.inserir(sobreescrever: boolean);
begin
  if (existeRegistro AND (not(sobreescrever))) then
    exit;

  if existeRegistro then
    atualizarRegistro
  else
    inserirRegistro;
end;

//*********************************************************************************//
//M�todo: inserirRegistro                                                          //
//Descri��o: Manda ao BD a senten�a de inser��o com os par�metros preenchidos.     //
//*********************************************************************************//
procedure TAlteradorBD.inserirRegistro;
var
  query: TosSQLDataSet;
begin
  query := TosSQLDataSet.Create(nil);
  try
    query.SQLConnection := MainData.SQLConnection;
    query.CommandText := getInsert;
    preencheParams(query);
    query.ExecSQL;
  finally
    freeAndNil(query);
  end;
end;

//*********************************************************************************//
//M�todo: preencheParams                                                           //
//Descri��o: Baseando-se nos par�metros da query, preenche seus valores conforme   //
//           a lista de valores                                                    //
//*********************************************************************************//
procedure TAlteradorBD.preencheParams(query: TosSQLDataSet);
var
  i, indiceCampo: integer;
  nomeParam: string;
begin
  for i := 0 to query.Params.Count-1 do
  begin
    nomeParam := query.Params[i].Name;
    indiceCampo := nomesCampos.IndexOf(nomeParam);
    if indiceCampo=-1 then
      raise exception.Create(E_CHAVE_SEM_VALOR);
    query.Params[i].Value    := TPropsCampo(nomesCampos.Objects[indiceCampo]).Valor;
    query.Params[i].DataType := TPropsCampo(nomesCampos.Objects[indiceCampo]).Tipo;
    if (query.Params[i].DataType=ftBlob) then
      TBlobField(query.Params[i]).BlobType := TPropsCampo(nomesCampos.Objects[indiceCampo]).SubTipo;
  end;
end;

//*********************************************************************************//
//M�todo: setarValor                                                               //
//Descri��o: Altera o valor de um campo                                            //
//*********************************************************************************//
procedure TAlteradorBD.setarSubTipo(PNome: string; PSubTipo: TBlobType);
var
  indiceCampo: integer;
begin
  indiceCampo := nomesCampos.IndexOf(PNome);
  if indiceCampo=-1 then
    raise exception.Create(E_CAMPO_INEXISTENTE);
  TPropsCampo(nomesCampos.Objects[indiceCampo]).SubTipo := PSubTipo;
end;

procedure TAlteradorBD.setarValor(PNome: string; PValor: variant);
var
  indiceCampo: integer;
begin
  indiceCampo := nomesCampos.IndexOf(PNome);
  if indiceCampo=-1 then
    raise exception.Create(E_CAMPO_INEXISTENTE);
  TPropsCampo(nomesCampos.Objects[indiceCampo]).Valor := PValor;
end;

end.
