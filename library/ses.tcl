# 
# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2026 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.
# 

package require pure-tcl-aws-core 0.1.0
namespace eval ::aws::ses {namespace path ::aws::core}
::aws::core::register ses {send_email send_raw_email send_templated_email create_template update_template get_template delete_template list_templates test_render_template verify_email_identity verify_domain_identity verify_domain_dkim list_identities get_identity_verification_attributes get_identity_dkim_attributes delete_identity get_send_quota get_send_statistics get_account_sending_enabled}

# Run a response reader while ensuring its XML document is always released.
proc ::aws::ses::call {client action fields reader {retry 0}} {
    set doc [query $client $action 2010-12-01 $fields $retry]
    try {
        set root [lindex [nodes [$doc documentElement] ${action}Result] 0]
        if {$root eq {}} {set root [$doc documentElement]}
        return [{*}$reader $root]
    } finally {$doc delete}
}

# Discard an operation's empty result.
proc ::aws::ses::empty {root} {return}

# Flatten a validated list into numbered AWS Query members.
proc ::aws::ses::members {prefix values {min 0} {max 1000}} {
    set count [llength $values]
    if {$count < $min || $count > $max} {error "$prefix must contain between $min and $max entries"}
    set fields {}; set i 0
    foreach value $values {
        if {$value eq {}} {error "list entries must not be empty"}
        lappend fields $prefix.member.[incr i] $value
    }
    return $fields
}

# Flatten common sending options shared by raw and structured messages.
proc ::aws::ses::common_fields {message} {
    set fields {}
    foreach {key field} {from Source source_arn SourceArn return_path_arn ReturnPathArn configuration_set ConfigurationSetName} {
        if {[dict exists $message $key]} {lappend fields $field [dict get $message $key]}
    }
    if {[dict exists $message tags]} {
        set i 0
        dict for {key value} [dict get $message tags] {incr i; lappend fields Tags.member.$i.Name $key Tags.member.$i.Value $value}
    }
    return $fields
}

# Flatten the structured envelope and validate the combined recipient count.
proc ::aws::ses::envelope {message} {
    required $message from
    set fields [common_fields $message]; set count 0
    foreach {key field} {to ToAddresses cc CcAddresses bcc BccAddresses} {
        if {[dict exists $message $key]} {
            set values [dict get $message $key]; incr count [llength $values]
            lappend fields {*}[members Destination.$field $values 0 50]
        }
    }
    if {$count < 1 || $count > 50} {error "provide between 1 and 50 recipients across to, cc and bcc"}
    if {[dict exists $message reply_to]} {lappend fields {*}[members ReplyToAddresses [dict get $message reply_to]]}
    if {[dict exists $message return_path]} {lappend fields ReturnPath [dict get $message return_path]}
    return $fields
}

# Extract the accepted message ID.
proc ::aws::ses::message_id {root} {xget $root MessageId}

# Send text, HTML, or both with explicit UTF-8 content.
proc ::aws::ses::_send_email {client message} {
    options $message {from to cc bcc subject text html reply_to return_path configuration_set tags source_arn return_path_arn}
    if {![dict exists $message subject]} {error "missing option: subject"}
    if {![dict exists $message text] && ![dict exists $message html]} {error "provide text or html (or both)"}
    set fields [envelope $message]
    lappend fields Message.Subject.Data [dict get $message subject] Message.Subject.Charset UTF-8
    foreach {key field} {text Text html Html} {
        if {[dict exists $message $key]} {lappend fields Message.Body.$field.Data [dict get $message $key] Message.Body.$field.Charset UTF-8}
    }
    call $client SendEmail $fields ::aws::ses::message_id
}

# Send raw MIME bytes, optionally overriding envelope addresses.
proc ::aws::ses::_send_raw_email {client bytes {opts {}}} {
    options $opts {from destinations source_arn from_arn return_path_arn configuration_set tags}
    if {![string length $bytes]} {error "mime_bytes must not be empty"}
    set fields [common_fields $opts]
    lappend fields RawMessage.Data [binary encode base64 -maxlen 0 $bytes]
    if {[dict exists $opts from_arn]} {lappend fields FromArn [dict get $opts from_arn]}
    if {[dict exists $opts destinations]} {
        set values [dict get $opts destinations]
        if {[llength $values] < 1 || [llength $values] > 50} {error "destinations must contain between 1 and 50 recipients"}
        lappend fields {*}[members Destinations $values 1 50]
    }
    call $client SendRawEmail $fields ::aws::ses::message_id
}

# Send a stored template with caller-supplied JSON substitutions.
proc ::aws::ses::_send_templated_email {client message} {
    options $message {from to cc bcc reply_to return_path configuration_set tags source_arn return_path_arn template template_data template_arn}
    set fields [envelope $message]
    lappend fields Template [required $message template] TemplateData [required $message template_data]
    if {[dict exists $message template_arn]} {lappend fields TemplateArn [dict get $message template_arn]}
    call $client SendTemplatedEmail $fields ::aws::ses::message_id
}

# Validate and flatten a stored email template.
proc ::aws::ses::template_fields {value} {
    options $value {name subject text html}
    set fields [list Template.TemplateName [required $value name]]
    if {![dict exists $value subject]} {error "missing option: subject"}
    if {![dict exists $value text] && ![dict exists $value html]} {error "provide text or html (or both)"}
    foreach {key field} {subject SubjectPart text TextPart html HtmlPart} {if {[dict exists $value $key]} {lappend fields Template.$field [dict get $value $key]}}
    return $fields
}

# Create a reusable email template.
proc ::aws::ses::_create_template {client value} {call $client CreateTemplate [template_fields $value] ::aws::ses::empty}

# Replace an existing template definition.
proc ::aws::ses::_update_template {client value} {call $client UpdateTemplate [template_fields $value] ::aws::ses::empty}

# Read template fields using the legacy lowercase names.
proc ::aws::ses::template_result {root} {
    set result {}; foreach {key field} {name TemplateName subject SubjectPart text TextPart html HtmlPart} {dict set result $key [xget $root Template/$field]}; return $result
}

# Fetch an email template.
proc ::aws::ses::_get_template {client name} {call $client GetTemplate [list TemplateName $name] ::aws::ses::template_result 1}

# Remove an email template.
proc ::aws::ses::_delete_template {client name} {call $client DeleteTemplate [list TemplateName $name] ::aws::ses::empty}

# Flatten explicit pagination options without fetching additional pages.
proc ::aws::ses::pagination {opts max} {
    set fields {}
    if {[dict exists $opts max_items]} {lappend fields MaxItems [integer [dict get $opts max_items] 1 $max max_items]}
    if {[dict exists $opts next_token]} {lappend fields NextToken [dict get $opts next_token]}
    return $fields
}

# Decode a page of template metadata.
proc ::aws::ses::templates_result {root} {
    set values {}
    foreach n [nodes $root TemplatesMetadata/member] {lappend values [dict create name [xget $n Name] created_timestamp [xget $n CreatedTimestamp]]}
    return [dict create templates $values next_token [xget $root NextToken]]
}

# List one page of templates and expose the next token.
proc ::aws::ses::_list_templates {client {opts {}}} {
    options $opts {max_items next_token}
    call $client ListTemplates [pagination $opts 100] ::aws::ses::templates_result 1
}

# Read the rendered MIME template.
proc ::aws::ses::rendered_result {root} {xget $root RenderedTemplate}

# Render a template without sending email.
proc ::aws::ses::_test_render_template {client name data} {call $client TestRenderTemplate [list TemplateName $name TemplateData $data] ::aws::ses::rendered_result 1}

# Request a verification email for an address.
proc ::aws::ses::_verify_email_identity {client email} {call $client VerifyEmailIdentity [list EmailAddress $email] ::aws::ses::empty}

# Extract the domain's DNS verification token.
proc ::aws::ses::verification_result {root} {xget $root VerificationToken}

# Request a domain verification token.
proc ::aws::ses::_verify_domain_identity {client domain} {call $client VerifyDomainIdentity [list Domain $domain] ::aws::ses::verification_result}

# Extract the DKIM DNS tokens.
proc ::aws::ses::dkim_result {root} {xlist $root DkimTokens/member}

# Request the domain's DKIM DNS tokens.
proc ::aws::ses::_verify_domain_dkim {client domain} {call $client VerifyDomainDkim [list Domain $domain] ::aws::ses::dkim_result}

# Decode a page of identity names.
proc ::aws::ses::identities_result {root} {dict create identities [xlist $root Identities/member] next_token [xget $root NextToken]}

# List one page of identities, optionally filtered by identity type.
proc ::aws::ses::_list_identities {client {opts {}}} {
    options $opts {max_items next_token identity_type}
    set fields [pagination $opts 1000]
    if {[dict exists $opts identity_type]} {
        set type [dict get $opts identity_type]
        if {$type ni {Domain EmailAddress}} {error "identity_type must be EmailAddress or Domain"}
        lappend fields IdentityType $type
    }
    call $client ListIdentities $fields ::aws::ses::identities_result 1
}

# Decode identity verification attributes into a name-keyed dictionary.
proc ::aws::ses::verification_attributes {root} {
    set result {}
    foreach entry [nodes $root VerificationAttributes/entry] {dict set result [xget $entry key] [dict create verification_status [xget $entry value/VerificationStatus] verification_token [xget $entry value/VerificationToken]]}
    return $result
}

# Decode DKIM status and tokens for each identity.
proc ::aws::ses::dkim_attributes {root} {
    set result {}
    foreach entry [nodes $root DkimAttributes/entry] {dict set result [xget $entry key] [dict create dkim_enabled [boolean [xget $entry value/DkimEnabled false]] dkim_verification_status [xget $entry value/DkimVerificationStatus] dkim_tokens [xlist $entry value/DkimTokens/member]]}
    return $result
}

# Validate identity lists before issuing an attribute request.
proc ::aws::ses::identity_fields {identities} {
    if {[llength $identities] < 1 || [llength $identities] > 100} {error "identities must contain between 1 and 100 entries"}
    members Identities $identities 1 100
}

# Get verification status for up to one hundred identities.
proc ::aws::ses::_get_identity_verification_attributes {client identities} {call $client GetIdentityVerificationAttributes [identity_fields $identities] ::aws::ses::verification_attributes 1}

# Get DKIM status for up to one hundred identities.
proc ::aws::ses::_get_identity_dkim_attributes {client identities} {call $client GetIdentityDkimAttributes [identity_fields $identities] ::aws::ses::dkim_attributes 1}

# Delete an identity from SES.
proc ::aws::ses::_delete_identity {client identity} {call $client DeleteIdentity [list Identity $identity] ::aws::ses::empty}

# Preserve fractional sending quotas.
proc ::aws::ses::quota_result {root} {
    set result {}; foreach {key field} {max_24_hour_send Max24HourSend max_send_rate MaxSendRate sent_last_24_hours SentLast24Hours} {dict set result $key [expr {double([xget $root $field 0])}]}; return $result
}

# Fetch the account's sending quotas.
proc ::aws::ses::_get_send_quota {client} {call $client GetSendQuota {} ::aws::ses::quota_result 1}

# Decode sending statistics without truncating 64-bit counters.
proc ::aws::ses::statistics_result {root} {
    set result {}
    foreach point [nodes $root SendDataPoints/member] {
        set value [dict create timestamp [xget $point Timestamp]]
        foreach {key field} {delivery_attempts DeliveryAttempts bounces Bounces complaints Complaints rejects Rejects} {dict set value $key [expr {wide([xget $point $field 0])}]}
        lappend result $value
    }
    return $result
}

# Fetch recent sending statistics.
proc ::aws::ses::_get_send_statistics {client} {call $client GetSendStatistics {} ::aws::ses::statistics_result 1}

# Decode the account sending flag.
proc ::aws::ses::enabled_result {root} {boolean [xget $root Enabled false]}

# Report whether SES sending is enabled for the account.
proc ::aws::ses::_get_account_sending_enabled {client} {call $client GetAccountSendingEnabled {} ::aws::ses::enabled_result 1}
package provide pure-tcl-aws-ses 0.1.0
package provide awsses 1.0.19
