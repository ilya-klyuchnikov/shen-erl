%%%-------------------------------------------------------------------
%%% @author Sebastian Borrazas
%%% @copyright (C) 2018, Sebastian Borrazas
%%%-------------------------------------------------------------------
-module(shen_erl_kl_primitives).

%% API
-export([fun_mfa/1,
         'if'/3,
         'simple-error'/1,
         'error-to-string'/1,
         'intern'/1,
         'set'/2,
         'value'/1,
         'number?'/1,
         'string?'/1,
         'pos'/2,
         'tlstr'/1,
         'str'/1,
         'cn'/2,
         'string->n'/1,
         'n->string'/1,
         'absvector'/1,
         'address->'/3,
         '<-address'/2,
         'absvector?'/1,
         'cons?'/1,
         'cons'/2,
         'hd'/1,
         'tl'/1,
         'write-byte'/2,
         'read-byte'/1,
         'open'/2,
         'close'/1,
         '='/2,
         'eval-kl'/1,
         'get-time'/1,
         'type'/2]).

-export(['symbol?'/1]).
-export([dynamic_app/1]).

%%%===================================================================
%%% API
%%%===================================================================

-spec fun_mfa(atom()) -> {ok, mfa()} | not_found.
fun_mfa('+') -> {ok, {erlang, '+', 2}};
fun_mfa('-') -> {ok, {erlang, '-', 2}};
fun_mfa('*') -> {ok, {erlang, '*', 2}};
fun_mfa('/') -> {ok, {erlang, '/', 2}};
fun_mfa('and') -> {ok, {erlang, 'and', 2}};
fun_mfa('or') -> {ok, {erlang, 'or', 2}};
fun_mfa('>') -> {ok, {erlang, '>', 2}};
fun_mfa('<') -> {ok, {erlang, '<', 2}};
fun_mfa('>=') -> {ok, {erlang, '>=', 2}};
fun_mfa('<=') -> {ok, {erlang, '<=', 2}};
fun_mfa('if') -> {ok, {?MODULE, 'if', 3}};
fun_mfa('simple-error') -> {ok, {?MODULE, 'simple-error', 1}};
fun_mfa('error-to-string') -> {ok, {?MODULE, 'error-to-string', 1}};
fun_mfa('intern') -> {ok, {?MODULE, 'intern', 1}};
fun_mfa('set') -> {ok, {?MODULE, 'set', 2}};
fun_mfa('value') -> {ok, {?MODULE, 'value', 1}};
fun_mfa('number?') -> {ok, {?MODULE, 'number?', 1}};
fun_mfa('string?') -> {ok, {?MODULE, 'string?', 1}};
fun_mfa('pos') -> {ok, {?MODULE, 'pos', 2}};
fun_mfa('tlstr') -> {ok, {?MODULE, 'tlstr', 1}};
fun_mfa('str') -> {ok, {?MODULE, 'str', 1}};
fun_mfa('cn') -> {ok, {?MODULE, 'cn', 2}};
fun_mfa('string->n') -> {ok, {?MODULE, 'string->n', 1}};
fun_mfa('n->string') -> {ok, {?MODULE, 'n->string', 1}};
fun_mfa('absvector') -> {ok, {?MODULE, 'absvector', 1}};
fun_mfa('address->') -> {ok, {?MODULE, 'address->', 3}};
fun_mfa('<-address') -> {ok, {?MODULE, '<-address', 2}};
fun_mfa('absvector?') -> {ok, {?MODULE, 'absvector?', 1}};
fun_mfa('cons?') -> {ok, {?MODULE, 'cons?', 1}};
fun_mfa('cons') -> {ok, {?MODULE, 'cons', 2}};
fun_mfa('hd') -> {ok, {?MODULE, 'hd', 1}};
fun_mfa('tl') -> {ok, {?MODULE, 'tl', 1}};
fun_mfa('write-byte') -> {ok, {?MODULE, 'write-byte', 2}};
fun_mfa('read-byte') -> {ok, {?MODULE, 'read-byte', 1}};
fun_mfa('open') -> {ok, {?MODULE, 'open', 2}};
fun_mfa('close') -> {ok, {?MODULE, 'close', 1}};
fun_mfa('=') -> {ok, {?MODULE, '=', 2}};
fun_mfa('eval-kl') -> {ok, {?MODULE, 'eval-kl', 1}};
fun_mfa('get-time') -> {ok, {?MODULE, 'get-time', 1}};
fun_mfa('type') -> {ok, {?MODULE, 'type', 2}};

fun_mfa('symbol?') -> {ok, {?MODULE, 'symbol?', 1}};

fun_mfa(_) -> not_found.

%% if
'if'(true, TrueVal, _FalseVal) -> TrueVal;
'if'(false, _TrueVal, FalseVal) -> FalseVal.

%% simple-error
'simple-error'({string, ErrorMsg}) -> throw({kl_error, ErrorMsg}).

%% error-to-string
'error-to-string'(Error) ->
  {string, Error}.

%% intern
intern({string, SymbolStr}) -> list_to_atom(SymbolStr).

%% set
set(Name, Val) when is_atom(Name) ->
  shen_erl_global_stores:set_val(Name, Val),
  Val.

%% value
value(Key) when is_atom(Key) ->
  case shen_erl_global_stores:get_val(Key) of
    {ok, Val} -> Val;
    not_found -> 'simple-error'({string, io_lib:format("Value not found for key `~p`", [Key])})
  end.

%% number?
'number?'(Val) when is_number(Val) -> true;
'number?'(_Val) -> false.

%% string?
'string?'({string, _Str}) -> true;
'string?'(_Val) -> false.

%% pos
pos({string, Str}, Index) when Index =< length(Str) ->
  {string, string:substr(Str, Index + 1, 1)};
pos({string, _Str}, Index) ->
  'simple-error'({string, io_lib:format("Index `~B` out of bounds.", [Index])}).

%% tlstr
tlstr({string, [_H | T]}) -> {string, T};
tlstr({string, []}) -> 'simple-error'({string, "Cannot call tlstr on an empty string."}).

%% str
str(Val) when is_atom(Val) ->
  {string, atom_to_list(Val)};
str({string, Str}) ->
  {string, lists:flatten(io_lib:format("~p", [Str]))};
str(Val) when is_function(Val) ->
  {string, lists:flatten(io_lib:format("FUN: ~p", [Val]))};
str(Val) when is_number(Val) ->
  {string, lists:flatten(io_lib:format("~p", [Val]))};
str(Val) when is_pid(Val) ->
  {string, lists:flatten(io_lib:format("PID: ~p", [Val]))};
str({cons, Car, Cdr}) ->
  {string, StrCar} = str(Car),
  {string, StrCdr} = str(Cdr),
  {string, lists:flatten(io_lib:format("(~s, ~s)", [StrCar, StrCdr]))};
str({vector, Vec}) ->
  {string, lists:flatten(io_lib:format("VECTOR: ~p", [Vec]))};
str([]) ->
  {string, "[]"}.

%% cn
cn({string, Str1}, {string, Str2}) -> {string, Str1 ++ Str2}.

%% string->n
'string->n'({string, [Char | _RestStr]}) -> Char;
'string->n'({string, []}) ->
  'simple-error'({string, "Cannot call string->n on an empty string."}).

%% n->string
'n->string'(Char) -> {string, [Char]}.

%% absvector
absvector(Length) ->
  {ok, Vec} = shen_erl_kl_vector:new(Length),
  {vector, Vec}.

%% address->
'address->'({vector, Vec}, Index, Val) ->
  shen_erl_kl_vector:set(Vec, Index, Val),
  {vector, Vec}.

%% <-address
'<-address'({vector, Vec}, Index) ->
  case shen_erl_kl_vector:get(Vec, Index) of
    {ok, Val} -> Val;
    out_of_bounds -> 'simple-error'({string, "Index out of bounds"})
  end.

%% absvector?
'absvector?'({vector, _Vec}) -> true;
'absvector?'(_Val) -> false.

%% cons?
'cons?'({cons, _H, _T}) -> true;
'cons?'(_Val) -> false.

%% cons
cons(H, T) -> {cons, H, T}.

%% hd
hd({cons, H, _T}) -> H;
hd(_Val) -> 'simple-error'({string, "Not a cons"}).

%% tl
tl({cons, _H, T}) -> T;
tl(_Val) -> 'simple-error'({string, "Not a cons"}).

%% write-byte
'write-byte'(Num, Stream) ->
  io:fwrite(Stream, "~c", [Num]).

%% read-byte
'read-byte'(Stream) ->
  case io:get_chars(Stream, [], 1) of
    [Char] -> Char;
    eof -> -1
  end.

%% open
open({string, FilePath}, in) ->
  {string, HomePath} = value('*home-directory*'),
  FileAbsPath = filename:absname(FilePath, HomePath),
  io:format(standard_error, "OPENING: ~p~n", [FileAbsPath]),
  {ok, File} = file:open(FileAbsPath, [read]),
  File;
open({string, FilePath}, out) ->
  {string, HomePath} = value('*home-directory*'),
  FileAbsPath = filename:absname(FilePath, HomePath),
  {ok, File} = file:open(FileAbsPath, [write]),
  File.

%% close
close(Stream) ->
  file:close(Stream),
  [].

%% =
'='(Val1, Val2) ->
  Val1 =:= Val2.

%% eval-kl
'eval-kl'(KlCode) ->
  KlCodeFlat = flatten_kl_code(KlCode),
  shen_erl_kl_compiler:eval_kl(KlCodeFlat).

%% get-time
'get-time'(unix) ->
  Epoch = calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}),
  calendar:datetime_to_gregorian_seconds(calendar:universal_time()) - Epoch;
'get-time'(run) ->
  Epoch = calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}), % TODO
  calendar:datetime_to_gregorian_seconds(calendar:universal_time()) - Epoch.

%% type
type(Val, _Hint) -> Val.

'symbol?'(Val) when is_atom(Val) -> true;
'symbol?'(_Val) -> false.

dynamic_app(Op) when is_atom(Op) ->
  case shen_erl_global_stores:get_mfa(Op) of
    {ok, {Mod, Fun, 0}} ->
      fun () -> Mod:Fun() end;
    {ok, {Mod, Fun, Arity}} ->
      nest_calls(Mod, Fun, Arity, []);
    not_found ->
      %% io:format(standard_error, "TAB TO LIST: ~p~n", [ets:tab2list('_kl_funs_store')]),
      %% io:format(standard_error, "ARITY OF ~p: ~p~n", [Op, kl_declarations:arity(Op)]),
      %% Op
      %% 'simple-error'({string, "Not a function: " ++ atom_to_list(Op)})
      throw({erriz, "Not a function: " ++ atom_to_list(Op)})
  end.

%%%===================================================================
%%% Internal functions
%%%===================================================================

flatten_kl_code({cons, Car, Cdr}) ->
  case flatten_kl_code(Cdr) of
    FlattenedCdr when is_list(FlattenedCdr) -> [flatten_kl_code(Car) | FlattenedCdr]
%% ;
%%     FlattenedCdr -> {cons, flatten_kl_code(Car), FlattenedCdr}
  end;
flatten_kl_code(Code) ->
  Code.

nest_calls(Mod, Fun, 0, Args) ->
  erlang:apply(Mod, Fun, lists:reverse(Args));
nest_calls(Mod, Fun, Arity, Args) ->
  fun (Arg) -> nest_calls(Mod, Fun, Arity - 1, [Arg | Args]) end.
