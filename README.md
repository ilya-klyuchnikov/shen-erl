# shen-erl

Erlang port of the Shen programming language.

## Building


```
make kl
make lexer
make parser
make
make shen-kl
make shen-tests
```

## Installation

TODO

## Running

For instructions on how to use the shen-erl command, run

```
./bin/shen-erl --help
```

## Erlang tests

Erlang tests are run through Docker:

```
make docker-test
# also run dialyzer
make docker-dialzye
```

## Shen tests

```
make shen-tests
```
