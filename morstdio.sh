#!/bin/sh

#feel free to change:
#morse input and output durations
#commands (in resolve_message) (e.g. ":w "=enter)
#feedback blinking (in resolve_message) (e.g. "-.." when caps is activated)

#todo: make a command and light feedback dictionary to make this easier

#issues: may be an issue with inputting ": " being interpreted as a command

# --- Settings ---
pollrate=0.025

#input lengths (ms)
dashdur=100 #duration of button press to be considered a dash instead of a dot
chardur=200 #duration of button release to start a new character
spacedur=400 #duration of button press for space

#output blink lengths (s)
dotlength=0.08 #also intermark pause
dashlength=0.2 #also intercharacter pause
longlength=0.5

capitaldotlength=0.16 #captial letters use longer tones (but not longer pauses)
capitaldashlength=0.4

#hardware location
BUTTON="/sys/bus/iio/devices/iio:device0/in_voltage1_raw"
LIGHT="/sys/class/leds/work-led/brightness"
echo "0" > "$LIGHT" #start with the light off

#aliases for convenience
alias e="echo"


# ---- Init ----
char="" #code for the character being constructed
message="" #full ascii message so far
stdout="" #most recent command output
stdin="" #most recent command input
clipboard="" #copied text
caps="off" #uppercase
skip=false #used for the button listener
ts=0 #timestamp, used to determine press/release duration
elapsed=0 #time since timestamp
pressdur=0 #duration of press during a "wait for user input" call
error=false #was the last stdout an error?
NEWLINE='
'

# ---- Listening ----
timestamp() { echo "$(date +"%s%3N")"; }
while_pressed() {
	ts="$(timestamp)"
	#loop while button pressed
	while [ "$(cat $BUTTON)" -lt "100" ]; do
		if $skip; then :;
		else
			elapsed="$(($(timestamp) - ts))"
			if [ "$elapsed" -gt "$spacedur" ]; then #held for long enough to trigger a space
				flash 1 0.3 0.06 #space feedback; not async
				push_message "$char" && message="$message " #add space if the last character was valid
				resolve_message #sets skip to true, ignoring the next pause
				char=""
			fi
		fi
		sleep "$pollrate"
	done
	#push dot or dash
	if ! $skip; then
        if [ "$elapsed" -gt "$dashdur" ]; then char="$char-"
    	else char="$char."; fi
	fi

	#check layers
}
while_released() {
	ts="$(timestamp)"
	#loop while button not pressed
	while [ "$(cat $BUTTON)" -gt "100" ]; do
		if $skip; then :;
		else
			elapsed="$(($(timestamp) - $ts))"
			if [ "$elapsed" -gt "$chardur" ]; then #held long enough to start a new character
				aflash 1 0.06 0 #charpause feedback
				push_message "$char"
				resolve_message
				char=""
			fi
		fi
		sleep "$pollrate"
	done
	skip=false
}
listen() { while true; do while_released; while_pressed; done }

# ---- Parsing ----
push_message(){ #add most recent code as ascii to message
	test "$1" = "" && return 0 #don't push anything if given empty input

	#backspace
	if [ "$1" = "-.-.-" ]; then 
		aflash 2 0.06 0.06
		message="${message%?}"
		return 0 #escape before trying to interpret $1 as a character
	#caps
	elif [ "$1" = "...---" ]; then 
		case "$caps" in
			"off") #turn on
				(flash 1 0.2 0.06; flash 2 0.06 0.06 &) #feedback
				caps="on"
			;;
			"on") #lock
				({
					flash 1 0.2 0.06; flash 2 0.06 0.06
					sleep 0.2
					flash 1 0.2 0.06; flash 2 0.06 0.06 
 				} &) #on indicator, twice
				caps="lock"
			;;
			"lock") #unlock
				(flash 1 0.2 0.06; flash 2 0.06 0.06; flash 1 0.2 0.06 &)
				caps="off" 
			;;
		esac
		return 0
	fi

	char="$(to_ascii "$1")"
	if [ ! "$caps" = "off" ]; then
		char="$(echo "$char" | tr "[:lower:]" "[:upper:]")" #apply caps
	elif [ "$caps" = "on" ]; then
		caps="off" #turn off caps
	fi

	if [ "$char" = "" ]; then   #error if invalid character
		aflash 4 0.06 0.06 #invalid character feedback
		return 1
	else 
		message="$message$char" #append to message
	fi
}
resolve_message() {
	
	#check commands
	if cmnd ":w "; then #enter message
		transmit "- - -"
		execute "$message"
		message=""
		caps="off"

	elif cmnd ":s "; then #delete most recent word
		(transmit ".... _" &) #feedback
		message="${message%${message##*[! ]}}" #remove trailing whitespace
		message="${message%${message##* }}" #remove characters up to the last whitespace

	elif cmnd ":sx "; then #abort message and try again
		#this feedback intentionally interrupts input for a little
		flash 3 0.06 0.06; flash 1 0.5 0.2; flash 3 0.06 0.06; flash 1 0.5 0
		message=""

	elif cmnd ": "; then #remove failed command (delete to most recent ":")
		aflash 2 0.06 0.06
		message="${message%?${message##*:}}" #remove characters up to the last :


	elif cmnd ":cp "; then #cut message
		(transmit ".... -.-." &) #feedback
		clipboard="$message"
		message=""

	elif cmnd ":cw "; then #copy last word
		(transmit "-.-. ..-" &) #"cw"
		clipboard="${message##* }"

	elif cmnd ":p "; then #paste
		aflash 3 0.12 0.06
		message="$message$clipboard"


	elif cmnd ":a "; then #repeat last word
		atransmit ".-. .-." #"rr" roger roger
		atransmit "$(morsify "${message##* }")"

	elif cmnd ":m "; then #repeat message
		atransmit ".-. .-. ==" #"rr M"
		atransmit "$(morsify "$message")"

	elif cmnd ":r "; then #repeat last stdout
		transmit ".-. .-." #"rr -----"
		echo "1" > "$LIGHT" #opaque = "full message incoming"
		await_input
		echo "0" > "$LIGHT"
		atransmit "$(morsify "$stdout")"

	elif cmnd ":c "; then #repeat last message (stdin)
		transmit ".. -. .. -." #"inin -----"
		echo "1" > "$LIGHT"
		await_input
		echo "0" > "$LIGHT"
		atransmit "$(morsify "$stdin")"


	elif cmnd ":q "; then #qrs last stdout (word by word, hold to exit early)
		atransmit "==*=" #"Q"
		qrs "$stdout"

	elif cmnd ":qm "; then #qrs message
		atransmit "==*= ==" #"Q M"
		qrs "$message"

	fi

	printf "\r%s\033[K" "$message"
	skip=true #stop checking duration
}
cmnd() { #check if a command has been entered (last characters in message match $1)
	length=$((${#1} + 1)) #length of input + 1
	if [ "$(echo "$message" | tail -c "$length")" = "$1" ]; then
		message="$(echo "$message" | head -c "-$length")" #remove command from message
		return 0
	else return 1
	fi
}

# ---- Interface ----
await_input() { #pause until button is pressed and released
	while [ "$(cat $BUTTON)" -gt "100" ]; do sleep "$pollrate"; done 
	ts="$(timestamp)"
	while [ "$(cat $BUTTON)" -lt "100" ]; do sleep "$pollrate"; done 
	pressdur="$(($(timestamp) - $ts))" #record button press duration
}
await_release() { while [ "$(cat $BUTTON)" -lt "100" ]; do sleep "$pollrate"; done } #just wait until the button is no longer pressed
execute() {
	#eval in main process
	tmp="/tmp/.morse"
	eval "$1" > "$tmp" 2>&1
	if [ "$?" -eq 0 ]; then error=false; else error=true; fi
	stdin="$1"
	stdout="$(cat "$tmp")"
	rm "$tmp"

	printf "\r%s\033[K\n\n%s\n" "$stdin" "$stdout"

	interface
}

interface() {
	echo "1" > "$LIGHT" #light on when message is ready
	await_input #wait until the next input (ignore how long the button press is)
	echo "0" > "$LIGHT" #turn off light before starting message

	if $error; then flash 7 0.06 0.06; fi #flash if stdout is error

	sleep 0.25

	atransmit "$(morsify "$stdout") _ _ _" #ends in three long dashes
	flash 1 1 0.25; flash 2 0.06 0.06 #ready for input
}


# ---- Lights ---- 
flash() { #flash [count] [ontime] [offtime]
	for c in $(seq 1 $1); do 
		echo 1 > $LIGHT
		sleep $2
		echo 0 > $LIGHT
		sleep $3
	done
}
aflash() { (flash $1 $2 $3 &); } #async flash

transmit() { #uncancellable, automatic
	code="$1"
	while [ ! "$code" = "" ]; do
		mark="${code%"${code#?}"}" #extract first character from string
		code="${code#?}" #remove first character from string

		if [ "$mark" = "." ]; then flash 1 "$dotlength" "$dotlength"
		elif [ "$mark" = "-" ]; then flash 1 "$dashlength" "$dotlength"
		elif [ "$mark" = "_" ]; then flash 1 "$longlength" "$dotlength" #long dash, for newline
		elif [ "$mark" = '*' ]; then flash 1 "$capitaldotlength" "$dotlength"
		elif [ "$mark" = "=" ]; then flash 1 "$capitaldashlength" "$dotlength"
		else sleep "$dashlength"
		fi
	done
}

atransmit() { #cancellable, requires input to continue
	#annoying workaround to avoid printing job
	tmp="/tmp/.morse"
	(transmit "$1" & echo $! > "$tmp") #transmit $1
	pid=$(cat "$tmp")
	rm "$tmp"

	await_input #wait for user input
	echo "0" > "$LIGHT" #turn off light in case it's interrupted while on

	kill -- $pid 2> /dev/null #kill process if it's not done yet
}

qrs() { #atransmit word-by-word. press button for next word. escape by holding button down
	for word in $(echo "$1" | sed 's#/# /#g'); do #split by space and slash (so pathnames are easier)
    	while true; do
			atransmit "$(morsify "$word")" #waits for next button press
			if [ "$pressdur" -gt 2000 ]; then #exit qrs if held for over two seconds
				flash 4 0.06 0.06 #not async
				break 2
			elif [ "$pressdur" -gt "$spacedur" ]; then #if held somewhat, repeat word
				flash 1 0.7 0 #not async
			else break; fi #otherwise go on to next word
		done
	done
	transmit "_ _ _" #signal end
}

# ---- Translation ----

morsify() {
	str="$1"
	code=""
	while [ ! "$str" = "" ]; do
		char="${str%"${str#?}"}" #extract first character from string
		str="${str#?}" #remove first character from string

		code="$code$(to_morse "$char")"
	done
	echo "$code"
}

to_ascii() { echo "$dictionary" | grep -Fe " $1 " | head -c 1; }
to_morse() { 
	#space, newline, period, and hyphen break the grep logic and are easier to handle manually
	if [ "$1" = " " ]; then echo "  "
	elif [ "$1" = "$NEWLINE" ]; then echo "_  "
	elif [ "$1" = "." ]; then echo ".-.-.- "
	elif [ "$1" = "-" ]; then echo ".-.- "
	else echo "$dictionary" | grep -Fe "$1 " | tail -c +3; 
	fi
}
NEWLINE='
' # $'\n' is a bashism ;(

#one of the limitations of this system is that it's hard to tell when there are leading/trailing/multiple spaces, but I don't think it's that important 


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
^ .--.. 
~ .-.-- 

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

A *= 
B =*** 
C =*=* 
D =** 
E * 
F **=* 
G ==* 
H **** 
I ** 
J *=== 
K =*= 
L *=** 
M == 
N =* 
O === 
P *==* 
Q ==*= 
R *=* 
S *** 
T = 
U **= 
V ***= 
W *== 
X =**= 
Y =*== 
Z ==** 
'
