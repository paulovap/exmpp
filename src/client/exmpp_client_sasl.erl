%% Copyright ProcessOne 2006-2010. All Rights Reserved.
%%
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.

%% @author Jean-Sébastien Pédron <js.pedron@meetic-corp.com>

%% The module <strong>{@module}</strong> implements the initiating
%% entity side of SASL authentication.
%%
%% <p>
%% Note that it doesn't implement SASL, only feature negotiation at the
%% XMPP level.
%% </p>

-module(exmpp_client_sasl).

-include("exmpp.hrl").

%% Feature announcement.
-export([
    announced_mechanisms/1
]).

%% SASL exchange.
-export([
    selected_mechanism/1,
    selected_mechanism/2,
    response/1,
    abort/0,
    next_step/1
]).


%%
-export_type([
  challenge/0
]).

-type(initial_response() :: binary()).
-type(challenge() :: binary()).

-export_type([
  xmlel_auth/0,
  xmlel_response/0,
  xmlel_abort/0
]).

-type(xmlel_auth()
  :: #xmlel{
         name     :: <<_:32>>,
         attrs    :: [
             {XmlNS     :: <<_:40>>, NS_SASL::<<_:256>>}           |
             {Mechanism :: <<_:72>>, exmpp_server_sasl:mechanism()},...
         ],
         children :: []
                   | [{'cdata',
                       Initial_Response::exmpp_client_sasl:initial_response()},...]
     }
).

-type(xmlel_response()
  :: #xmlel{
         name     :: <<_:64>>,
         attrs    :: [{XmlNS :: <<_:40>>, NS_SASL::<<_:256>>},...],
         children :: []
                   | [{'cdata', Challenge::exmpp_client_sasl:challenge()},...]
     }
).

-type(xmlel_abort()
  :: #xmlel{
         name     :: <<_:40>>,
         attrs    :: [{XmlNS :: <<_:40>>, NS_SASL::<<_:256>>},...],
         children :: []
     }
).

%%
-define(Xmlel@SASL(Name, Attrs, Children),
(
    exxml:element(?NS_SASL, Name, Attrs, Children)
)).


%% --------------------------------------------------------------------
%% Feature announcement.
%% --------------------------------------------------------------------

%% @throws {sasl, announced_mechanisms, invalid_feature, Feature} |
%%         {sasl, announced_mechanisms, invalid_mechanism, El}
%% @doc Return the list of SASL mechanisms announced by the receiving entity.
-spec(announced_mechanisms/1 ::
(
  Xmlel_Features :: exmpp_stream:xmlel_features() | exxml:el())
    -> Mechanisms :: exmpp_server_sasl:mechanisms()
).

announced_mechanisms(Xmlel_Features) 
  when   Xmlel_Features#xmlel.name == <<"features">>
  orelse Xmlel_Features#xmlel.name == <<"stream:features">> ->
    case exxml:get_element(Xmlel_Features, <<"mechanisms">>) of
        undefined        -> [];
        Xmlel_Mechanisms -> announced_mechanisms2(Xmlel_Mechanisms)
    end.

%%
-spec(announced_mechanisms2/1 ::
(
  Xmlel_Mechanisms::exmpp_server_sasl:xmlel_mechanisms())
    -> Mechanisms::exmpp_server_sasl:mechanisms()
).

announced_mechanisms2(Xmlel_Mechanisms)
  when Xmlel_Mechanisms#xmlel.children == [] ->
    throw({sasl, announced_mechanisms, 'invalid_feature', Xmlel_Mechanisms});
announced_mechanisms2(Xmlel_Mechanisms) ->
    announced_mechanisms3(exxml:get_elements(Xmlel_Mechanisms), []).

%%
-spec(announced_mechanisms3/2 ::
(
  Xmlels_Mechanism :: [Xmlel_Mechanism::exmpp_server_sasl:xmlel_mechanism(),...],
  Mechanisms       :: [] | exmpp_server_sasl:mechanisms())
    -> Mechanisms::exmpp_server_sasl:mechanisms()
).

announced_mechanisms3([Xmlel_Mechanism | Xmlels], Mechanisms)
  when Xmlel_Mechanism#xmlel.name == <<"mechanism">> ->
    case exxml:get_cdata(Xmlel_Mechanism) of
        <<>> ->
            throw({sasl, announced_mechanisms, 'invalid_mechanism', Xmlel_Mechanism});
        Mechanism ->
            announced_mechanisms3(Xmlels, [Mechanism | Mechanisms])
    end;
announced_mechanisms3([Xmlel | _Xmlels], _Mechanisms) ->
    throw({sasl, announced_mechanisms, 'invalid_mechanism', Xmlel});
announced_mechanisms3([], Mechanisms) ->
    lists:reverse(Mechanisms).

%% --------------------------------------------------------------------
%% SASL exchange.
%% --------------------------------------------------------------------

%% @doc Prepare an `<auth/>' element with the selected mechanism.
-spec(selected_mechanism/1 ::
(
  Mechanism::exmpp_server_sasl:mechanism())
    -> Xmlel_Auth::exmpp_client_sasl:xmlel_auth()
).

selected_mechanism(Mechanism) ->
    ?Xmlel@SASL(<<"auth">>, [{<<"mechanism">>, Mechanism}], []).

%% @doc Prepare an `<auth/>' element with the selected mechanism.
%%
%% The initial response will be Base64-encoded before inclusion.
-spec(selected_mechanism/2 ::
(
  Mechanism       :: exmpp_server_sasl:mechanism(),
  Intial_Response :: exmpp_client_sasl:initial_response())
    -> Xmlel_Auth::exmpp_sasl_client:xmlel_auth()
).

selected_mechanism(Mechanism, <<>>) ->
    Xmlel_Auth = selected_mechanism(Mechanism),
    exxml:append_child(Xmlel_Auth, {cdata, <<"=">>});
selected_mechanism(Mechanism, Initial_Response) ->
    Xmlel_Auth = selected_mechanism(Mechanism),
    exxml:append_child(Xmlel_Auth, {cdata, base64:encode(Initial_Response)}).

%% @doc Prepare a `<response/>' element to send the challenge's response.
%%
%% `Response_Data' will be Base64-encoded.
-spec(response/1 ::
(
  Response_Data::exmpp_client_sasl:challenge() | string())
    -> Xmlel_Response::exmpp_client_sasl:xmlel_response()
).

response(Response_Data) ->
    ?Xmlel@SASL(<<"response">>, [], [{cdata, base64:encode(Response_Data)}]).

%% @doc Make a `<abort/>' element.
-spec(abort/0 :: () -> Xmlel_Abort::exmpp_client_sasl:xmlel_abort()).

abort() ->
    ?Xmlel@SASL(<<"abort">>, [], []).

%% @doc Extract the challenge or the ending element that the receiving
%% entity sent.
%%
%% Any challenge or success data is Base64-decoded.
%-spec(next_step/1 ::
%(
%  Xmlel_Challenge :: exmpp_server_sasl:xmlel_challenge())
%    -> {'challenge', Challenge::exmpp_server_sasl:challenge()} ;
%(
%  Xmlel_Failure :: exmpp_server_sasl:xmlel_failure())
%    -> {'failure', Error_Condition :: exmpp_server_sasl:error_condition() | undefined} ;
%(
%  Xmlel_Success :: exmpp_server_sasl:xmlel_success())
%    -> {'success', exmpp_server_sasl:additional_data()}
%).
-spec(next_step/1 ::
(
  Xmlel :: exmpp_server_sasl:xmlel_challenge()
         | exmpp_server_sasl:xmlel_failure()
         | exmpp_server_sasl:xmlel_success())
    -> {'challenge', Challenge::exmpp_server_sasl:challenge()}
     | {'failure',   Error_Condition :: exmpp_server_sasl:error_condition() | undefined}
     | {'success',   exmpp_server_sasl:additional_data()}
).


next_step(Xmlel_Challenge) when Xmlel_Challenge#xmlel.name == <<"challenge">> ->
    {'challenge', base64:decode(exxml:get_cdata(Xmlel_Challenge))};
next_step(Xmlel_Failure) when Xmlel_Failure#xmlel.name == <<"failure">> ->
    case exxml:get_elements(Xmlel_Failure) of
        [#xmlel{name = Error_Condition}] ->
            {'failure', Error_Condition};
        _ ->
            {'failure', undefined}
    end;
next_step(Xmlel_Success) when Xmlel_Success#xmlel.name == <<"success">> ->
    {'success', base64:decode(exxml:get_cdata(Xmlel_Success))}.
