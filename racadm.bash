#! /bin/bash

#
# Thanks to ( https://github.com/migrantgeek/python-racadm ) ..
# .. for the pointers on required url and xml for requests.
#
# Currently, the command line options are based on:
# ( https://cs.uwaterloo.ca/~brecht/servers/docs/PowerEdge-2600/en/Racadm/racadmc1.htm )
#

function _racadm_bash_help ()
#
#
#
{

	cat <<-EOF

	racadm.bash <options> -u <user name> -p <password> -r <racIpAddr> <subcommand>

	EOF

	#racadm.bash <options> <subcommand> <subcommand_options>
	#racadm.bash <options> [-u <user name>] -p <password> -r <racIpAddr> <subcommand>
	#racadm.bash <options> -i -r <racIpAddr> <subcommand>
	#racadm.bash <options> -r <racIpAddr> <subcommand>

	exit 1

}

function _racadm_bash_init ()
#
#
#
{

	set -a

	_racadm_ip_def=127.0.0.1
	_racadm_un_def=racadmusr
	_racadm_pw_def=calvin
	_racadm_ip=
	_racadm_un=
	_racadm_pw=
	_racadm_use_int_unpw=0
	_racadm_use_netrc=0
	_racadm_cmd=()

	set +a

}

function _racadm_bash ()
#
#
#
{

	_racadm_bash_init

	_racadm_bash_opts "${@}"

	_racadm_exec

}

function _racadm_bash_opts ()
#
#
#
{

	declare -a ARGV=( "${@}" )

	declare {I,V}=
	declare HLP=0

	[ -z "${ARGV[*]}" ] && HLP=1

	printf "%s\n" "${ARGV[@]}" |
		grep -qi "^--*he*l*p*\$" \
		&& HLP=1

	[ "${HLP}" -ne 1 ] || _racadm_bash_help

	for (( I=0; I<${#ARGV[@]}; I++ ))
	do
		V="${ARGV[${I}]}"
		case "${V}" in
			( -r ) {
				_racadm_ip="${ARGV[$((++I))]}"
			};;
			( -u ) {
				_racadm_un="${ARGV[$((++I))]}"
			};;
			( -p ) {
				_racadm_pw="${ARGV[$((++I))]}"
			};;
			( -i ) {
				_racadm_use_int_unpw=1
			};;
			( -n ) {
				_racadm_use_netrc=1
			};;
			( -* ) { _racadm_bash_help "${V}"; };;
			( * ) { break; };;
		esac
	done

	for (( I=${I}; I<${#ARGV[@]}; I++ ))
	do
		_racadm_cmd[${#_racadm_cmd[@]}]="${ARGV[${I}]}"
	done

	[ -n "${_racadm_un}" -a -z "${_racadm_pw}" ] && \
		_racadm_bash_help
	[ "${_racadm_use_int_unpw}" -eq 1 -o "${_racadm_use_netrc}" -eq 1 ] && \
	[ -n "${_racadm_un}" -o -n "${_racadm_pw}" ] && \
		_racadm_bash_help
	[ "${_racadm_use_netrc}" -eq 1 -a -z "${_racadm_ip}" ] && \
		_racadm_bash_help

	_racadm_ip="${_racadm_ip:-${_racadm_ip_def}}"
	_racadm_un="${_racadm_un:-${_racadm_un_def}}"
	_racadm_pw="${_racadm_pw:-${_racadm_pw_def}}"

}

function _racadm_exec ()
{

	declare {TMP,HDR,OUT,SID}=

	declare -a CMD=(
		curl
		-qsk
		-X POST
		-D ">( sed \"s/^/= /\" 1>&2; )"
		-d @-
	)

	TMP="$( { {
		cat <<-EOF | eval "${CMD[@]}" "https://${_racadm_ip}/cgi-bin/login"
			<?xml version='1.0'?>
			<LOGIN><REQ><USERNAME>${_racadm_un}</USERNAME><PASSWORD>${_racadm_pw}</PASSWORD></REQ></LOGIN>
		EOF
	} | sed "s/^/. /"; } 2>&1; )"
	HDR="$( echo "${TMP}" | sed -n "s/^= //p" )"
	OUT="$( echo "${TMP}" | sed -n "s/^\. //p" )"
	unset TMP
	{ echo "${HDR}" | grep -nw 200 | grep -q ^1:; } \
	&& {
		SID="$( echo "${OUT}" | sed -n "s=.*<SID>\(.*\)</SID>.*=\1=p"; )"
	}
	[ -z "${SID}" ] && _racadm_fail "${HDR}" "${OUT}"

	TMP="$( { {
		cat <<-EOF | eval "${CMD[@]}" "https://${_racadm_ip}/cgi-bin/exec" --cookie "sid=${SID}"
			<?xml version='1.0'?>
			<EXEC><REQ><CMDINPUT>racadm ${_racadm_cmd[@]}</CMDINPUT><MAXOUTPUTLEN>0x0fff</MAXOUTPUTLEN></REQ></EXEC>
		EOF
	} | sed "s/^/. /"; } 2>&1; )"
	HDR="$( echo "${TMP}" | sed -n "s/^= //p" )"
	OUT="$( echo "${TMP}" | sed -n "s/^\. //p" )"
	unset TMP
	{ echo "${HDR}" | grep -nw 200 | grep -q ^1:; } \
	&& {
		echo "${OUT}" |
			sed -n "/<CMDOUTPUT>/,/<\/CMDOUTPUT>/p" |
			sed "1s/.*<CMDOUTPUT>//;\$s/<\/CMDOUTPUT>.*//" |
			sed "s/\&lt\;/</g;s/\&gt\;/>/g;s/\&amp\;/\&/g"
	} \
	|| {
		_racadm_fail "${HDR}" "${OUT}"
	}

}

_racadm_bash "${@}"

exit 0
