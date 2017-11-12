InteractiveFileLineNumber=0

interactive_mode() {
  local ast code compiled_code line="" state=none
  local proc rfifo wfifo end_token result
  local powhistory="${POWSCRIPT_HISTORY_FILE-$HOME/.powscript_history}"
  local extra_line=''
  local compile_flag=false ast_flag=false echo_flag=false

  [ ! -f "$powhistory" ] && echo >"$powhistory"
  history -c
  history -r "$powhistory"

  powscript_make_fifo ".interactive.wfifo" wfifo
  powscript_make_fifo ".interactive.rfifo" rfifo
  powscript_temp_name ".end" end_token

  interactive_compile_target "$wfifo" "$rfifo" "$end_token" &
  proc="$!"

  exec 3<>"$wfifo"
  exec 4<>"$rfifo"

  while ps -p $proc >/dev/null; do
    result=

    if [ -n "$extra_line" ]; then
      line="$extra_line"
      extra_line=""
    else
      read_powscript top line
    fi
    code="$line"

    case "$code" in
      '.compile')
        toggle_flag compile_flag
        ;;
      '.ast')
        toggle_flag ast_flag
        ;;
      '.echo')
        toggle_flag echo_flag
        ;;
      '.show '*)
        show_ast "${code//.show /}"
        echo
        ;;
      *)
        state=none
        while [ ! $state = top ]; do
          ast_clear_all
          clear_all_tokens
          state="$( { init_stream; try_parse_ast; } <<< "$code" )"
          case "$state" in
            top)
              ast_clear_all
              clear_all_tokens
              { init_stream; parse_ast ast; } <<< "$code"$'\n'
              ;;
            error*)
              >&2 echo "$state"
              state=none
              code=
              ;;
            *)
              read_powscript $state line
              code="$code"$'\n'"$line"
              ;;
          esac
        done
        if [ ! "$line" = '' ] && [ ! "$line" = "$code" ]; then
          code="$(echo "$code" | head -n -1)"$'\n'
          extra_line="$line"
        fi

        history -s "$code"

        if $echo_flag; then
          echo "---- CODE ECHO -----"
          echo "$code"
          echo "---------------------"
         fi

        if $ast_flag; then
          echo "---- SYNTAX TREE ----"
          show_ast $ast
          echo "---------------------"
        fi
        compile_to_backend $ast compiled_code
        if $compile_flag; then
          echo "--- COMPILED CODE ---"
          echo "$compiled_code"
          echo "---------------------"
        fi
        echo "$compiled_code" >>"$wfifo"
        echo "#<<END>>" >>"$wfifo"
        while [ ! "$result" = "#<<END.$end_token>>" ]; do
          IFS= read -r result <"$rfifo"
          [ ! "$result" = "#<<END.$end_token>>" ] && echo "$result"
        done
        echo
        ;;
    esac
  done
  history -w "$powhistory"

  rm $wfifo
  rm $rfifo
}

show_ast() {
  echo "id:       $1"
  echo "head:     $(from_ast $1 head)"
  echo "value:    $(from_ast $1 value)"
  echo "children: $(from_ast $1 children)"
  ast_print $1
}

toggle_flag() {
  if ${!1}; then
    setvar "$1" false
  else
    setvar "$1" true
  fi
}

read_powscript() {
  IFS="" read -r -e -p "$(format_powscript_prompt "$1")" "$2"
  InteractiveFileLineNumber=$((InteractiveFileLineNumber+1))
}

format_powscript_prompt() {
  local state_name=$1 state

  case $state_name in
    top) state="--" ;;
    double-quotes) state='""' ;;
    single-quotes) state="''" ;;
    *) state="$state_name" ;;

  esac

  local default_prompt='pow[%L]%S> '
  local prompt="${POWSCRIPT_PS1-$default_prompt}"

  prompt="${prompt//%L/$(printf '%.3d' $InteractiveFileLineNumber)}"
  prompt="${prompt//%S/$(printf '%3s'  $state)}"

  echo "$prompt"
}


