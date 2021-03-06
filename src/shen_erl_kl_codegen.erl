%%%-------------------------------------------------------------------
%%% @author Sebastian Borrazas
%%% @copyright (C) 2018, Sebastian Borrazas
%%%-------------------------------------------------------------------
-module(shen_erl_kl_codegen).

%% API
-export([load_defuns/2,
         eval/1,
         compile/1,
         compile/3]).

%% Macros
-define(ERL_TRUE, erl_syntax:atom(true)).
-define(ERL_FALSE, erl_syntax:atom(false)).

%% Types
-type form() :: erl_syntax:syntaxTree().

-record(code, {signatures :: [form()],
               forms :: [form()],
               tles :: [form()]}).

%%%===================================================================
%%% API
%%%===================================================================

-spec load_defuns(module(), shen_erl_kl_parse:kl_tree()) -> ok.
load_defuns(Mod, ToplevelDefs) ->
  [shen_erl_global_stores:set_mfa(Name, {Mod, Name, length(Args)}) ||
    [defun, Name, Args, _Body] <- ToplevelDefs, is_atom(Name), is_list(Args)],
  ok.

-spec eval(shen_erl_kl_parse:kl_tree()) -> term().
eval(ToplevelDef) ->
  {ok, Mod, Bin} = compile(ToplevelDef),
  {module, Mod} = code:load_binary(Mod, [], Bin),
  Mod:kl_tle().

-spec compile(shen_erl_kl_parse:kl_tree()) -> {ok, module(), binary()} |
                                              {error, binary()}.
compile(ToplevelDef = [defun, Name, Args, _Body]) ->
  Mod = modname(Name),
  shen_erl_global_stores:set_mfa(Name, {Mod, Name, length(Args)}),
  compile(Mod, [ToplevelDef], Name);
compile(ToplevelDef) ->
  compile(rand_modname(32, []), [ToplevelDef], ok).

-spec compile(module(), shen_erl_kl_parse:kl_tree(), atom()) -> {ok, binary()} |
                                                                {error, binary()}.
compile(Mod, ToplevelDefs, DefaultTle) ->
  compile_toplevel(Mod, ToplevelDefs, #code{signatures = [],
                                            forms = [],
                                            tles = [erl_syntax:atom(DefaultTle)]}).

%%%===================================================================
%%% Internal functions
%%%===================================================================

compile_toplevel(Mod, [[defun, Name, Args, Body] | Rest], Code = #code{signatures = Sigs,
                                                                       forms = Forms}) ->
  Env = shen_erl_kl_env:new(),
  UnusedVars = [Arg || Arg <- Args, is_unused(Arg, Body)],
  {ArgsCode, Env2} = fun_vars(Args, Env, UnusedVars),
  BodyCode = compile_exp(Body, Env2),
  Clause =  erl_syntax:clause(ArgsCode, [], [BodyCode]),
  Function = erl_syntax:function(erl_syntax:atom(Name), [Clause]),
  FunForm = erl_syntax:revert(Function),

  Signature = erl_syntax:arity_qualifier(erl_syntax:atom(Name), erl_syntax:integer(length(Args))),
  compile_toplevel(Mod, Rest, Code#code{signatures = [Signature | Sigs],
                                        forms = [FunForm | Forms]});
compile_toplevel(Mod, [Exp | Rest], Code = #code{tles = Tles}) when is_list(Exp) ->
  Env = shen_erl_kl_env:new(),
  BodyCode = compile_exp(Exp, Env),
  compile_toplevel(Mod, Rest, Code#code{tles = [BodyCode | Tles]});
compile_toplevel(Mod, [_Exp | Rest], Code) ->
  compile_toplevel(Mod, Rest, Code);
compile_toplevel(Mod, [], #code{signatures = Sigs, forms = Forms, tles = Tles}) ->
  ModAttr = erl_syntax:attribute(erl_syntax:atom(module), [erl_syntax:atom(Mod)]),
  ModForm = erl_syntax:revert(ModAttr),

  TleSignature = erl_syntax:arity_qualifier(erl_syntax:atom(kl_tle), erl_syntax:integer(0)),

  ExportAttr = erl_syntax:attribute(erl_syntax:atom(export), [erl_syntax:list([TleSignature | Sigs])]),
  ExportForm = erl_syntax:revert(ExportAttr),

  TleClause =  erl_syntax:clause([], [], lists:reverse(Tles)), % No args, no guards
  TleFunction = erl_syntax:function(erl_syntax:atom(kl_tle), [TleClause]),
  TleForm = erl_syntax:revert(TleFunction),

  case compile:forms([ModForm, ExportForm, TleForm | Forms]) of
    {ok, Mod, Bin} -> {ok, Mod, Bin};
    SomethingElse -> {error, SomethingElse}
  end.

%% Lists
compile_exp([], _Env) -> % ()
  erl_syntax:nil();

%% Boolean operators
compile_exp(['and', Exp1, Exp2], Env) -> % (and Exp1 Exp2)
  CExp1 = compile_exp(force_boolean(Exp1), Env),
  CExp2 = compile_exp(force_boolean(Exp2), Env),
  erl_syntax:infix_expr(CExp1, erl_syntax:operator("andalso"), CExp2);
compile_exp(['or', Exp1, Exp2], Env) -> % (or Exp1 Exp2)
  CExp1 = compile_exp(force_boolean(Exp1), Env),
  CExp2 = compile_exp(force_boolean(Exp2), Env),
  erl_syntax:infix_expr(CExp1, erl_syntax:operator("orelse"), CExp2);
compile_exp(['not', Exp], Env) -> % (not Exp)
  CExp = compile_exp(force_boolean(Exp), Env),
  erl_syntax:prefix_expr(erl_syntax:operator("not"), CExp);

%% Symbols and variables
compile_exp(Exp, Env) when is_atom(Exp) -> % a
  case shen_erl_kl_env:fetch(Env, Exp) of
    {ok, VarName} -> erl_syntax:variable(VarName);
    not_found -> erl_syntax:atom(Exp)
  end;

%% Numbers
compile_exp(Exp, _Env) when is_integer(Exp) -> % 1
  erl_syntax:integer(Exp);
compile_exp(Exp, _Env) when is_float(Exp) -> % 2.2
  erl_syntax:float(Exp);

%% Strings
compile_exp({string, Exp}, _Env) ->
  erl_syntax:tuple([erl_syntax:atom(string), erl_syntax:string(Exp)]);

%% lambda
compile_exp([lambda, Var, Body], Env) when is_atom(Var) -> % (lambda X (+ X 2))
  IsUnused = is_unused(Var, Body),
  {EVar, Env2} = shen_erl_kl_env:store_var(Env, Var, IsUnused),
  CBody = compile_exp(Body, Env2),
  Clause = erl_syntax:clause([erl_syntax:variable(EVar)], [], [CBody]),
  erl_syntax:fun_expr([Clause]);

%% let
compile_exp(['let', Var, ExpValue, Body], Env) when is_atom(Var) -> % (let X (+ 2 2) (+ X 3))
  CExpValue = compile_exp(ExpValue, Env),
  IsUnused = is_unused(Var, Body),
  {EVar, Env2} = shen_erl_kl_env:store_var(Env, Var, IsUnused),
  CBody = compile_exp(Body, Env2),
  Clause = erl_syntax:clause([erl_syntax:variable(EVar)], none, [CBody]),
  erl_syntax:case_expr(CExpValue, [Clause]);

%% if
compile_exp(['if', Exp, ExpTrue, ExpFalse], Env) ->
  CExp = compile_exp(force_boolean(Exp), Env),
  CExpTrue = compile_exp(ExpTrue, Env),
  CExpFalse = compile_exp(ExpFalse, Env),
  TrueClause = erl_syntax:clause([?ERL_TRUE], none, [CExpTrue]),
  FalseClause = erl_syntax:clause([?ERL_FALSE], none, [CExpFalse]),
  erl_syntax:case_expr(CExp, [TrueClause, FalseClause]);

%% cond
compile_exp(['cond', [Exp, ExpTrue]], Env) ->
  CExp = compile_exp(force_boolean(Exp), Env),
  CExpTrue = compile_exp(ExpTrue, Env),
  TrueClause = erl_syntax:clause([?ERL_TRUE], none, [CExpTrue]),
  erl_syntax:case_expr(CExp, [TrueClause]);

compile_exp(['cond', [Exp, ExpTrue] | Rest], Env) ->
  CExp = compile_exp(force_boolean(Exp), Env),
  CExpTrue = compile_exp(ExpTrue, Env),
  CExpFalse = compile_exp(['cond' | Rest], Env), % TODO: Check all the cond structure beforehand
  TrueClause = erl_syntax:clause([?ERL_TRUE], none, [CExpTrue]),
  FalseClause = erl_syntax:clause([?ERL_FALSE], none, [CExpFalse]),
  erl_syntax:case_expr(CExp, [TrueClause, FalseClause]);

%% Lazy values
compile_exp([freeze, Body], Env) ->
  CBody = compile_exp(Body, Env),
  Clause = erl_syntax:clause([], [], [CBody]),
  erl_syntax:fun_expr([Clause]);

%% Trap errors
compile_exp(['trap-error', Body, Handler], Env) ->
  {ErrorClassVarName, Env2} = shen_erl_kl_env:new_var(Env),
  {ErrorBodyVarName, _Env3} = shen_erl_kl_env:new_var(Env2),
  CBody = compile_exp(Body, Env),
  CHandlerFun = compile_exp(Handler, Env),
  CErrorClassVar = erl_syntax:variable(ErrorClassVarName),
  CErrorBodyVar = erl_syntax:variable(ErrorBodyVarName),
  CError = erl_syntax:tuple([CErrorClassVar, CErrorBodyVar]),
  CErrorQualifier = erl_syntax:class_qualifier(CErrorClassVar, CErrorBodyVar),
  CHandler = erl_syntax:clause([CErrorQualifier], none, [erl_syntax:application(CHandlerFun, [CError])]),
  erl_syntax:try_expr([CBody], [CHandler]);

%% Factorization
compile_exp(['%%let-label', [Label | Vars], LabelBody, Body], Env) ->
  {CVars, LabelBodyEnv} = lists:foldr(fun
                                (Var, {CVars, EnvAcc}) ->
                                  {VarName, EnvAcc2} =
                                    shen_erl_kl_env:store_var(EnvAcc, Var, false),
                                  {[erl_syntax:variable(VarName) | CVars], EnvAcc2}
                              end,
                              {[], Env},
                              Vars),
  CLabelBody = compile_exp(LabelBody, LabelBodyEnv),
  CClause = erl_syntax:clause(CVars, [], [CLabelBody]),
  CLetLabel = erl_syntax:fun_expr([CClause]),

  {LetVar, Env2} = shen_erl_kl_env:store_var(Env, Label, false),

  CBody = compile_exp(Body, Env2),
  CLetClause = erl_syntax:clause([erl_syntax:variable(LetVar)], none, [CBody]),

  erl_syntax:case_expr(CLetLabel, [CLetClause]);

compile_exp(['%%goto-label', Label | Args], Env) ->
  {ok, VarName} = shen_erl_kl_env:fetch(Env, Label),
  CArgs = [compile_exp(Arg, Env) || Arg <- Args],
  erl_syntax:application(erl_syntax:variable(VarName), CArgs);

compile_exp(['%%return', Exp], Env) ->
  compile_exp(Exp, Env);

%% Function call optimizations

compile_exp(['intern', {string, SymbolStr}], _Env) ->
  erl_syntax:atom(list_to_atom(SymbolStr));

compile_exp(['thaw', Exp], Env) ->
  compile_exp([Exp], Env);

%% Function applications

%% Case 1: Function operator is an atom
compile_exp([Op | Args], Env) when is_atom(Op) -> % (a b c)
  CArgs = [compile_exp(Arg, Env) || Arg <- Args],
  case shen_erl_kl_env:fetch(Env, Op) of
    {ok, VarName} ->
      %% Case 1.1: Function operator is a variable
      compile_dynamic_app(erl_syntax:variable(VarName), CArgs);
    not_found ->
      %% Case 1.2: Function operator is a global function
      case shen_erl_global_stores:get_mfa(Op) of
        {ok, {Mod, Fun, Arity}} ->
          COp = erl_syntax:module_qualifier(erl_syntax:atom(Mod), erl_syntax:atom(Fun)),
          compile_static_app(COp, Arity, CArgs, Env);
        not_found ->
          % NOTE: Assuming if function was not previously defined, then it's going to be called
          %       with the same number of arguments that it was defined.
          COp = erl_syntax:module_qualifier(erl_syntax:atom(modname(Op)), erl_syntax:atom(Op)),
          erl_syntax:application(COp, CArgs)
      end
  end;

%% Case 2: Function operator is not an atom
compile_exp([Op | Args], Env) ->
  COp = compile_exp(Op, Env),
  CArgs = [compile_exp(Arg, Env) || Arg <- Args],
  compile_dynamic_app(COp, CArgs).

compile_dynamic_app(COp, []) -> % Freezed expression application
  erl_syntax:application(COp, []);
compile_dynamic_app(COp, [CArg]) -> % Single argument application
  erl_syntax:application(COp, [CArg]);
compile_dynamic_app(COp, [CArg | RestCArgs]) -> % Multiple argument application
  compile_dynamic_app(compile_dynamic_app(COp, [CArg]), RestCArgs).

compile_static_app(COp, Arity, CArgs, _Env) when Arity =:= length(CArgs) ->
  erl_syntax:application(COp, CArgs);
compile_static_app(COp, Arity, CArgs, Env) when Arity > length(CArgs) ->
  {VarName, Env2} = shen_erl_kl_env:new_var(Env),
  CBody = compile_static_app(COp, Arity, CArgs ++ [erl_syntax:variable(VarName)], Env2),
  Clause = erl_syntax:clause([erl_syntax:variable(VarName)], [], [CBody]),
  erl_syntax:fun_expr([Clause]);
compile_static_app(COp, Arity, CArgs, Env) when Arity < length(CArgs) ->
  {StaticCArgs, DynamicCArgs} = lists:split(Arity, CArgs),
  compile_dynamic_app(compile_static_app(COp, Arity, StaticCArgs, Env), DynamicCArgs).

%% Helper functions
is_unused(Var, Var) ->
  false;
is_unused(Var, [lambda, Var, _Body]) ->
  true;
is_unused(Var, [lambda, _Var, Body]) ->
  is_unused(Var, Body);
is_unused(Var, ['let', Var, _ExpValue, _Body]) ->
  true;
is_unused(Var, ['let', _Var, ExpValue, Body]) ->
  is_unused(Var, ExpValue) andalso is_unused(Var, Body);
is_unused(Var, Exp) when is_list(Exp) ->
  lists:all(fun (E) -> is_unused(Var, E) end, Exp);
is_unused(_Var, _Exp) ->
  true.

fun_vars(Args, Env, UnusedVars) ->
  {Args2, Env2} = lists:foldl(fun (Var, Acc) -> fun_var(Var, UnusedVars, Acc) end,
                              {[], Env},
                              Args),
  {lists:reverse(Args2), Env2}.

fun_var(Var, UnusedVars, {Acc, Env}) when is_atom(Var) ->
  {EVar, Env2} = shen_erl_kl_env:store_var(Env, Var, lists:member(Var, UnusedVars)),
  {[erl_syntax:variable(EVar) | Acc], Env2}.

modname(Name) ->
  list_to_atom("_kl_" ++ atom_to_list(Name)).

rand_modname(0, Acc) ->
  list_to_atom("_kl_" ++ Acc);
rand_modname(N, Acc) ->
  rand_modname(N - 1, [rand:uniform(26) + 96 | Acc]).

yields_boolean(true) -> true;
yields_boolean(false) -> false;
yields_boolean(['let', _Var, _ExpValue, Body]) -> yields_boolean(Body);
yields_boolean(['do', _Exp1, Exp2]) -> yields_boolean(Exp2);
yields_boolean([Op, _Param1, _Param2]) when Op =:= 'or' orelse
                                            Op =:= 'and' orelse
                                            Op =:= '<' orelse
                                            Op =:= '>' orelse
                                            Op =:= '>=' orelse
                                            Op =:= '<=' orelse
                                            Op =:= '=' ->
  true;
yields_boolean([Op, _Param1]) when Op =:= 'not' orelse
                                   Op =:= 'string?' orelse
                                   Op =:= 'vector?' orelse
                                   Op =:= 'number?' orelse
                                   Op =:= 'cons?' orelse
                                   Op =:= 'absvector?' orelse
                                   Op =:= 'element?' orelse
                                   Op =:= 'symbol?' orelse
                                   Op =:= 'tuple?' orelse
                                   Op =:= 'variable?' orelse
                                   Op =:= 'boolean?' orelse
                                   Op =:= 'empty?' orelse
                                   Op =:= 'shen.pvar?' ->
  true;
yields_boolean(_Exp) -> false.

force_boolean(Exp) ->
  case yields_boolean(Exp) of
    true -> Exp;
    false -> ['assert-boolean', Exp]
  end.
