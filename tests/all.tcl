# 
# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2026 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.
# 

set here [file dirname [file normalize [info script]]]
if {[catch {exec python3 [file join $here ses_server.py] --library [file join $here .. pkgIndex.tcl] --tclsh [info nameofexecutable] >@stdout 2>@stderr} message]} {puts stderr $message; exit 1}
