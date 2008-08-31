%% @author Masahito Ikuta <cooldaemon@gmail.com> [http://d.hatena.ne.jp/cooldaemon/]
%% @copyright Masahito Ikuta 2008
%% @doc This module is utility for the list type data.

%% Copyright 2008 Masahito Ikuta
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(list_utils).
-author('cooldaemon@gmail.com').

-export([pmap/2, pmap/3, pmap/4]).
-export([pmap_coordinator/4, pmap_supervisor/4, pmap_worker/3]).
-export([split/2, split_map/3, split_foldl/4]).
-export([test/0]).

-define(SUPERVISOR_TIMEOUT, 500).

pmap(Fun, Lists) ->
  pmap(Fun, Lists, infinity).

pmap(Fun, Lists, Timeout) ->
  pmap(Fun, Lists, Timeout, infinity).

pmap(Fun, Lists, Timeout, WorkerTimeout) ->
  Pid = spawn_link(
    ?MODULE,
    pmap_coordinator,
    [self(), Fun, Lists, WorkerTimeout]
  ),
  receive
    {Pid, ack_pmap_coordinator, Results} ->
      Results
  after Timeout ->
    {error, timeout}
  end.

pmap_coordinator(ParentPid, Fun, Lists, WorkerTimeout) ->
  Pids = lists:map(
    fun (Arg) ->
      spawn_link(
        ?MODULE, pmap_supervisor, [self(), Fun, Arg, WorkerTimeout]
      )
    end,
    Lists
  ),
  ParentPid ! {
    self(), ack_pmap_coordinator, pmap_receive(Pids, WorkerTimeout)
  }.

pmap_receive(Pids, WorkerTimeout) -> 
  pmap_receive(Pids, WorkerTimeout, [], length(Pids)).

pmap_receive(Pids, _WorkerTimeout, Results, Count) when Count =< 0 ->
  lists:map(fun (Pid) -> proplists:get_value(Pid, Results) end, Pids);
pmap_receive(Pids, WorkerTimeout, Results, Count) ->
  Result = receive
    {Pid, ack_pmap_supervisor, AckResult} -> {Pid, AckResult}
  after pmap_supervisor_timeout(WorkerTimeout) ->
    {error, supervisor_timeout}
  end,
  pmap_receive(Pids, WorkerTimeout, [Result | Results], Count - 1).

pmap_supervisor_timeout(infinity) ->
  infinity;
pmap_supervisor_timeout(WorkerTimeout) ->
  WorkerTimeout + ?SUPERVISOR_TIMEOUT.

pmap_supervisor(ParentPid, Fun, Arg, WorkerTimeout) ->
  Pid = spawn_link(?MODULE, pmap_worker, [self(), Fun, Arg]),
  Result = receive
    {Pid, ack_pmap_worker, AckResult} ->
      AckResult
  after WorkerTimeout ->
    {error, worker_timeout}
  end,
  ParentPid ! {self(), ack_pmap_supervisor, Result}.

pmap_worker(ParentPid, Fun, Arg) ->
  ParentPid ! {self(), ack_pmap_worker, eval(Fun, [Arg])}.

eval(Fun, Args) ->
  try
    case Fun of
      {M, F} -> apply(M, F, Args);
      Fun    -> apply(Fun, Args)
    end
  catch
    Type:Reason ->
      {Type, Reason}
  end.

split(N, Lists) ->
  split(N, [], Lists).

split(0, Results, Lists) ->
  {lists:reverse(Results), Lists};
split(_N, Results, []) ->
  split(0, Results, []);
split(N, Results, [Elem | Lists]) ->
  split(N - 1, [Elem | Results], Lists).

split_map(Fun, N, Lists) ->
  split_map(Fun, N, split(N, Lists), []).

split_map(_Fun, _N, {[], []}, Results) ->
  lists:reverse(Results);
split_map(Fun, N, {Args, Lists}, Results) ->
  split_map(Fun, N, split(N, Lists), [eval(Fun, [Args]) | Results]).

split_foldl(Fun, Acc, N, Lists) ->
  split_foldl_loop(Fun, Acc, N, split(N, Lists)).

split_foldl_loop(_Fun, Acc, _N, {[], []}) ->
  Acc;
split_foldl_loop(Fun, Acc, N, {Args, Lists}) ->
  split_foldl_loop(Fun, eval(Fun, [Args, Acc]), N, split(N, Lists)).

test() ->
  test_pmap(),
  test_split(),
  test_split_map(),
  test_split_foldl(),
  ok.

test_pmap() ->
  Lists = lists:seq(1, 10),
  Results = lists:map(fun (N) -> N * N end, Lists),
  Results = pmap(fun (N) -> N * N end, Lists),
  ok.

test_split() ->
  Lists = lists:seq(1, 10),
  SubLists = lists:seq(3, 10),
  {[1, 2], SubLists} = split(2, Lists),
  {Lists, []} = split(10, Lists),
  {Lists, []} = split(11, Lists),
  ok.

test_split_map() ->
  Results = lists:seq(3, 19, 4),
  Results = split_map(
    fun ([A, B]) -> A + B end,
    2,
    lists:seq(1, 10)
  ),
  ok.

test_split_foldl() ->
  Results = lists:foldl(
    fun (N, Acc) -> N * Acc end,
    1,
    lists:seq(3, 19, 4)
  ),
  Results = split_foldl(
    fun ([A, B], Acc) -> (A + B) * Acc end,
    1,
    2,
    lists:seq(1, 10)
  ),
  ok.
