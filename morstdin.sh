#!/bin/sh
#Usage: ./morstdin <handler> & PID=$!
#kill -<signal> $PID (see below)
#2x long = send, -.-.- = delete last word, long+eee = start over

handler="$1" #user-defined action
evaluate() { printf "\n%s\n" "Sent: $1"; eval "$handler"; }

trap 'message="$message""."' SIGUSR1 	#dot
trap 'message="$message""-"' SIGUSR2 	#dash
trap 'message="$message"" = "' SIGHUP #long
trap 'message="$message"" "' SIGURG		#charspace

# ---- Translation ----
to_text() { for word in $1; do printf "%s" "$(to_ascii "$word")"; done; }
to_ascii() { echo "$dictionary" | grep -Fe " $1 " | head -c 1; }

# --- Dictionary ---
#important: all entries have trailing spaces
dictionary='
a .- 
b -... 
c -.-. 
d -.. 
e . 
f ..-. 
g --. 
h .... 
i .. 
j .--- 
k -.- 
l .-.. 
m -- 
n -. 
o --- 
p .--. 
q --.- 
r .-. 
s ... 
t - 
u ..- 
v ...- 
w .-- 
x -..- 
y -.-- 
z --.. 

1 .---- 
2 ..--- 
3 ...-- 
4 ....- 
5 ..... 
6 -.... 
7 --... 
8 ---.. 
9 ----. 
0 ----- 

$ ---. 
- .-.- 
" ..-- 
/ ---- 

. .-.-.- 
? ..--.. 
! -.-.-- 
= -...- 
, --..-- 

+ ..-.. 
* ...-. 
^ .--.- 
~ .--.- 

: --.-- 
; -.-.. 
| .---. 
\ ..--. 
_ ..-.- 
` ---.- 
'"' -.--- "'

% .-..- 
& --.-. 
# .-.-- 
@ --..- 

( ---... 
) .---...  
[ .--... 
] ..--... 
{ ..-...
} ...-...
< -..--- 
> .-..--- 

  = 
'

echo "PID: $$"
message=''
while true; do
  sleep 1 &
  wait $!

	printf "\033[2K\r%s" "$message"
  test "${message: -9}" = " = . . . " && message='' #reset
  test "${message: -7}" = " -.-.- " && message="${message%${message##*\=}} " #delete word
  test "${message: -6}" = " =  = " && evaluate "$(to_text "$message")" && message='' #send
done

