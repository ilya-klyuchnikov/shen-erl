%%%-------------------------------------------------------------------
%%% @author Sebastian Borrazas
%%% @copyright (C) 2018, Sebastian Borrazas
%%%-------------------------------------------------------------------
-module(shen_erl_kl_compiler).

%% API
-export([files_kl/2,
         eval_kl/1,
         eval/1,
         load/1]).

%% Macros
-define(KL_MODS, ['kl_core',
                  'kl_dict',
                  'kl_load',
                  'kl_prolog',
                  'kl_sequent',
                  'kl_t-star',
                  'kl_track',
                  'kl_writer',
                  'kl_declarations',
                  'kl_macros',
                  'kl_reader',
                  'kl_sys',
                  'kl_toplevel',
                  'kl_types',
                  'kl_yacc']).

%% Types
-type opt() :: {output_dir, string()}.

-export_type([opt/0]).

%%%===================================================================
%%% API
%%%===================================================================

-spec files_kl([string()], [opt()]) -> ok | {error, binary()}.
files_kl(Filenames, Opts) ->
  case parse_files(Filenames, []) of
    {ok, FilesAsts} -> compile_kl(FilesAsts, Opts);
    {error, Reason} -> {error, Reason}
  end.

-spec eval_kl(term()) -> ok. % TODO Type parameter
eval_kl(KlCode) ->
  case shen_erl_kl_codegen:compile(KlCode) of
    {ok, Mod, Bin} ->
      code:load_binary(Mod, [], Bin),
      {ok, Mod:kl_tle()};
    {error, Reason} -> {error, Reason}
  end.

-spec load(string()) -> ok | {error, binary()}.
load(Filename) ->
  load_funs(),
  kl_load:load({string, Filename}),
  ok.

-spec eval(string()) -> term().
eval(ShenCode) ->
  load_funs(),
  kl_sys:eval(ShenCode).

-spec start_repl() -> ok.
start_repl() ->
  load_funs(),
  kl_toplevel:'shen.shen'().

%%%===================================================================
%%% Internal functions
%%%===================================================================

load_funs() ->
  [[begin
      shen_erl_global_stores:set_mfa(FunName, {Mod, FunName, Arity}),
      Mod:kl_tle()
    end ||
    {FunName, Arity} <- Mod:module_info(exports),
    FunName =/= kl_tle, FunName =/= module_info] || Mod <- ?KL_MODS].

compile_kl([{Mod, Ast} | Rest], Opts) ->
  io:format(standard_error, "COMPILING ~p~n", [Mod]),
  case shen_erl_kl_codegen:compile(Mod, Ast) of
    {ok, Bin} ->
      case write(Mod, Bin, Opts) of
        ok -> compile_kl(Rest, Opts);
        {error, Reason} -> {error, Reason}
      end;
    {error, Reason} -> {error, Reason}
  end;
compile_kl([], _Opts) ->
  ok.

parse_files([Filename | Rest], Acc) ->
  case parse_kl_file(Filename) of
    {ok, Ast} ->
      Mod = list_to_atom("kl_" ++ filename:basename(Filename, ".kl")),
      shen_erl_kl_codegen:load_defuns(Mod, Ast),
      parse_files(Rest, [{Mod, Ast} | Acc]);
    {error, Reason} -> {error, Reason}
  end;
parse_files([], Acc) -> {ok, Acc}.

parse_kl_file(Filename) ->
  case file:open(Filename, [read]) of
    {ok, In} ->
      case io:request(In, {get_until, unicode, '', shen_erl_kl_scan, tokens, [1]}) of
        {ok, Tokens, _EndLine} ->
          shen_erl_kl_parse:parse_tree(Tokens);
        {error, Reason} ->
          io:format(standard_error, "ERROR: ~p~n", [Reason]),
          {error, Reason}
      end;
    {ErrorLine, Mod, Reason} ->
      io:format(standard_error, "ERROR: ~p, ~p, ~p~n", [ErrorLine, Mod, Reason]),
      {error, Reason}
  end.

write(Mod, BeamCode, Opts) ->
  {ok, CurrentDir} = file:get_cwd(),
  io:format(standard_error, "SAVING: ~p~n", [Mod]),
  OutputDir = proplists:get_value(output_dir, Opts, CurrentDir),
  case file:write_file(OutputDir ++ "/" ++ atom_to_list(Mod) ++ ".beam", BeamCode) of
    ok -> ok;
    {error, Reason} -> {error, Reason}
  end.

modname(Name) ->
  Name.

rand_modname() ->
  list_to_atom("_" ++ rand_modname(32, [])).

rand_modname(0, Acc) ->
  Acc;
rand_modname(N, Acc) ->
  rand_modname(N - 1, [rand:uniform(26) + 96 | Acc]).
