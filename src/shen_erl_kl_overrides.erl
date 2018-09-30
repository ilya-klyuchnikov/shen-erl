%%%-------------------------------------------------------------------
%%% @author Sebastian Borrazas
%%% @copyright (C) 2018, Sebastian Borrazas
%%%-------------------------------------------------------------------
-module(shen_erl_kl_overrides).

%% API
-export(['symbol?'/1]).

%%%===================================================================
%%% API
%%%===================================================================

'symbol?'(Val) when is_atom(Val) -> true;
'symbol?'(_Val) -> false.