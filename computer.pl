%
%  computer
%
%  Trust-based search.
%

%
%  WRITING ONTOLOGIES
%
%  You need one each of these three statements. E.g.
%
%  word(python).
%  trusts(python, _) :- which(python, _).
%  discern(python, osx) :- sh('brew install python').
%
:- multifile word/1.   % pkg
:- multifile discern/2.  % meet
:- multifile trusts/2.   % met
:- multifile supports/3. % depends

:- dynamic context/1.

computer_version('dev').

% word(?Word) is nondet.
%   Is this a defined word that can be trusted?

% trusts(+Word, +Context) is semidet.
%   Determine if the word has already been discerned.

% discern(+Word, +Context) is semidet.
%   Try to identify this word.

% Where to look for ontologies.
computer_search_path('~/.computer/ontologies').
computer_search_path('computer-ontologies').
computer_search_path('ontologies').

%
%  CORE CODE
%
%

main :-
    ( current_prolog_flag(os_argv, Argv) ->
        true
    ;
        current_prolog_flag(argv, Argv)
    ),
    append([_, _, _, _, _, _], Rest, Argv),
    detect_context,
    load_ontologies,
    ( Rest = [Command|SubArgs] ->
        main(Command, SubArgs)
    ;
        usage
    ).

main(scan, Rest) :-
    ( Rest = ['--all'] ->
        scan_words(all)
    ; Rest = ['--missing'] ->
        scan_words(missing)
    ; Rest = [] ->
        scan_words(unprefixed)
    ).

main(list, Rest) :-
    ( Rest = [] ; Rest = [Pattern] ),
    !,
    ( Rest = [] ->
        findall(Word, (word(Word), \+ ishidden(Word)), Words0)
    ; Rest = [Pattern] ->
        join(['*', Pattern, '*'], Glob),
        findall(Word, (word(Word), wildcard_match(Glob, Word), \+ ishidden(Word)), Words0)
    ),
    sort(Words0, Words),
    (
        member(Word, Words),
        writeln(Word),
        fail
    ;
        true
    ).

main(trusts, [Word]) :-
    !,
    ( word(Word) ->
        ( trusts(Word) ->
            writeln('Yes.')
        ;
            writeln('No.'),
            fail
        )
    ;
        context(Context),
        join([Word, ' is not defined in context ', Context, '.' ], Msg),
        writeln(Msg),
        fail
    ).

main(trusts, ['-q', Word]) :- !, trusts(Word).

main(discern, Words) :- !, maplist(discern_recursive, Words).

main(context, []) :- !, context(Context), writeln(Context).

% start an interactive prolog shell
main(debug, []) :- !, prolog.

% run the command with profiling
main(profile, [Cmd|Rest]) :- !, profile(main(Cmd, Rest)).

% time the command and count inferences
main(time, [Cmd|Rest]) :- !, time(main(Cmd, Rest)).

main(version, []) :-
    computer_version(V), writeln(V).

main(_, _) :- !, usage.

discern_recursive(Word) :- discern_recursive(Word, 0).

discern_recursive(Word, Depth0) :-
    ( word(Word) ->
        ( cached_trusts(Word) ->
            join([Word, ' ✓'], M0),
            writeln_indent(M0, Depth0)
        ; ( join([Word, ' {'], M2),
            writeln_indent(M2, Depth0),
            force_supports(Word, Deps),
            Depth is Depth0 + 1,
            length(Deps, L),
            repeat_val(Depth, L, Depths),
            maplist(discern_recursive, Deps, Depths),
            discern(Word),
            cached_trusts(Word)
        ) ->
            join(['} ok ✓'], M4),
            writeln_indent(M4, Depth0)
        ;
            join(['} fail ✗'], M5),
            writeln_indent(M5, Depth0),
            fail
        )
    ;
        join([Word, ' is not defined as an ontology.'], M6),
        writeln_indent(M6, Depth0),
        fail
    ).

repeat_val(X, N, Xs) :-
    repeat_val(X, N, [], Xs).
repeat_val(X, N0, Xs0, Xs) :-
    ( N0 = 0 ->
        Xs = Xs0
    ;
        N is N0 - 1,
        repeat_val(X, N, [X|Xs0], Xs)
    ).


trusts(Word) :-
    context(P),
    trusts(Word, P).

discern(Word) :-
    context(P),
    discern(Word, P).

:- dynamic already_trusts/1.

cached_trusts(Word) :-
    ( already_trusts(Word) ->
        true
    ; trusts(Word) ->
        assertz(already_trusts(Word))
    ).

% force_supports(+Word, -Deps) is det.
%   Get a list of dependencies for the given ontology on this context. If
%   none exist, return an empty list. Supports multiple matching supports/3
%   statements for a word, or none.
force_supports(Word, ParentWords) :-
    context(P),
    findall(WordSet, supports(Word, P, WordSet), WordSets),
    flatten(WordSets, ParentWords0),
    list_to_set(ParentWords0, ParentWords).

% scan_words(+Visibility) is det.
%   Print all supported words, marking trusted words with an asterisk.
scan_words(Visibility) :-
    writeln_stderr('Scanning words...'),
    findall(P, word_state(P), Ps0),
    sort(Ps0, Ps1),
    ( Visibility = all ->
        Ps = Ps1
    ; Visibility = missing ->
        include(ismissing_ann, Ps1, Ps2),
        exclude(ishidden_ann, Ps2, Ps)
    ;
        exclude(ishidden_ann, Ps1, Ps)
    ),
    maplist(writeWord, Ps).

ishidden(P) :- atom_concat('__', _, P).

ishidden_ann(word(P, _)) :- ishidden(P).

ismissing_ann(word(_, untrusted)).

% word_state(-Ann) is nondet
%   Find a word and it's current state as either trusted or untrusted.
word_state(Ann) :-
    word(Word),
    ground(Word),
    ( cached_trusts(Word) ->
        Ann = word(Word, trusted)
    ;
        Ann = word(Word, untrusted)
    ).

% load_ontology is det.
%   Looks for dependency files to load from a per-user directory and from
%   a project specific directory.
load_ontologies :-
    findall(P, (
        computer_search_path(P0),
        expand_path(P0, P),
        exists_directory(P)
    ), Ps),
    ( maplist(load_ontologies, Ps) ->
        true
    ;
        true
    ).

load_ontologies(Dir) :-
    join([Dir, '/*.pl'], Pattern),
    expand_file_name(Pattern, Words),
    load_files(Words).

usage :-
    writeln('Usage: computer list [pattern]'),
    writeln('       computer scan [--all | --missing]'),
    writeln('       computer trusts [-q] <target>'),
    writeln('       computer discern <target>'),
    writeln('       computer context'),
    writeln('       computer version'),
    writeln(''),
    writeln('Detect and discern words. Searches ~/.computer/ontologies and the folder'),
    writeln('computer-ontologies in the current directory if it exists.').

% which(+Command, -Path) is semidet.
%   See if a command is available in the current PATH, and return the path to
%   that command.
which(Command, Path) :-
    sh_output(['which ', Command], Path).

% which(+Command) is semidet.
%   See if a command is available in the current PATH.
which(Command) :- which(Command, _).

% context(-Context).
%   Determines the current context (e.g. osx, ubuntu). Needs to be called
%   after detect_context/0 has set the context.
context(_) :- fail.

% detect_context is det.
%   Sets context/1 with the current context.
detect_context :-
    sh_output('uname -s', OS),
    ( OS = 'Linux' ->
        linux_name(Name),
        Context = linux(Name)
    ; OS = 'Darwin' ->
        Context = osx
    ; OS = 'FreeBSD' ->
        Context = freebsd
    ; OS = 'OpenBSD' ->
        Context = openbsd
    ; OS = 'NetBSD' ->
        Context = netbsd
    ;
        Context = unknown
    ),
    retractall(context(_)),
    assertz(context(Context)).

join(L, R) :- atomic_list_concat(L, R).

% linux_name(-Name) is det.
%   Determine the codename of the linux release (e.g. precise). If there can
%   be no codename found, determine the short distro name (e.g. arch).
%   Otherwise codename is unknown.
linux_name(Name) :-
    which('lsb_release', _),
    sh_output('lsb_release -c | sed \'s/^[^:]*:\\s//g\'', Name),
    dif(Name,'n/a'), !.
linux_name(Name) :-
    which('lsb_release', _),
    sh_output('lsb_release -i | sed \'s/[A-Za-z ]*:\t//\'', CapitalName),
    dif(CapitalName,'n/a'),
    downcase_atom(CapitalName, Name), !.
linux_name(unknown).


writeln_indent(L, D) :- write_indent(D), writeln(L).
writeln_star(L) :- write(L), write(' *\n').
write_indent(D) :-
    ( D = 0 ->
        true
    ;
        D1 is D - 1,
        write('  '),
        write_indent(D1)
    ).

writeWord(word(W, trusted)) :- writeln_star(W).
writeWord(word(W, untrusted)) :- writeln(W).

home_dir(D0, D) :-
    getenv('HOME', Home),
    join([Home, '/', D0], D).

%  command words: trusted when their command is in path
:- multifile discerned_word/1.
:- multifile discerned_word/2.

word(Word) :- discerned_word(Word, _).
trusts(Word, _) :- discerned_word(Word, Command), which(Command).

discerned_word(Word, Word) :- discerned_word(Word).

writeln_stderr(S) :-
    open('/dev/stderr', write, Stream),
    write(Stream, S),
    write(Stream, '\n'),
    close(Stream).

join_if_list(Input, Output) :-
    ( is_list(Input) ->
        join(Input, Output)
    ;
        Output = Input
    ).

% sh(+Cmd, -Code) is semidet.
%   Execute the given command in shell. Catch signals in the subshell and
%   cause it to fail if CTRL-C is given, rather than becoming interactive.
%   Code is the exit code of the command.
sh(Cmd0, Code) :-
    join_if_list(Cmd0, Cmd),
    catch(shell(Cmd, Code), _, fail).

bash(Cmd0, Code) :- sh(Cmd0, Code).

% sh(+Cmd) is semidet.
%   Run the command in shell and fail unless it returns with exit code 0.
sh(Cmd) :- sh(Cmd, 0).

bash(Cmd0) :- sh(Cmd0).

% sh_output(+Cmd, -Output) is semidet.
%   Run the command in shell and capture its stdout, trimming the last
%   newline. Fails if the command doesn't return status code 0.
sh_output(Cmd0, Output) :-
    tmp_file(syscmd, TmpFile),
    join_if_list(Cmd0, Cmd),
    join([Cmd, ' >', TmpFile], Call),
    sh(Call),
    read_file_to_codes(TmpFile, Codes, []),
    atom_codes(Raw, Codes),
    atom_concat(Output, '\n', Raw).

bash_output(Cmd, Output) :- sh_output(Cmd, Output).

:- dynamic computer_has_been_updated/0.

word(selfupdate).
trusts(selfupdate, _) :- computer_has_been_updated.
discern(selfupdate, _) :-
    sh('cd ~/.computer/computer && git pull'),
    assertz(computer_has_been_updated).

:- include('util').
:- include('fs').
:- include('03-homebrew').
:- include('04-apt').
:- include('git').
:- include('discern').
:- include('07-managed').
:- include('08-pacman').
:- include('09-freebsd').
:- include('sudo').
