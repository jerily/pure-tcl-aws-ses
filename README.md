# pure-tcl-aws-ses

AWS SES client implemented in Tcl 9.1. Its only package dependency is
[`pure-tcl-aws-core`](https://github.com/jerily/pure-tcl-aws-core), which supplies
HTTP, JSON, XML, credentials and signing. No AWS C++ SDK is required.

```tcl
package require pure-tcl-aws-ses 1.0.0
set client [::aws::ses::create {region us-east-1}]
try {
    puts [$client get_send_quota]
} finally {
    $client destroy
}
```

`package require awsses 1.0.19` is also supported. Use one implementation
of the `awsses` package per interpreter. Existing namespace commands
(`::aws::ses::method $client ...`) and client methods share the same behavior.
Client destruction returns an empty result. Unknown methods and invalid arguments
raise Tcl errors. See the core README for credentials, configuration and retries.

## Methods

| Method | Arguments after the client handle |
| --- | --- |
| `send_email` | `message` |
| `send_raw_email` | `bytes ?opts?` |
| `send_templated_email` | `message` |
| `create_template` | `value` |
| `update_template` | `value` |
| `get_template` | `name` |
| `delete_template` | `name` |
| `list_templates` | `?opts?` |
| `test_render_template` | `name data` |
| `verify_email_identity` | `email` |
| `verify_domain_identity` | `domain` |
| `verify_domain_dkim` | `domain` |
| `list_identities` | `?opts?` |
| `get_identity_verification_attributes` | `identities` |
| `get_identity_dkim_attributes` | `identities` |
| `delete_identity` | `identity` |
| `get_send_quota` | — |
| `get_send_statistics` | — |
| `get_account_sending_enabled` | — |

## Behavior

This package implements the SES classic API, including raw MIME, templates, identities, DKIM and sending statistics. Text uses UTF-8; raw email accepts a byte array. Template and identity lists expose `next_token` for explicit pagination. Email sends are never automatically retried after an ambiguous failure. SESv2 is outside this release.

## Install and examples

Install the core and its dependencies first, then run:

```sh
make install PREFIX=/your/prefix
```

The release recipe declares examples with `file` entries. After registry installation:

```sh
ttrek run -package pure-tcl-aws-ses -script example-quota
ttrek run -package pure-tcl-aws-ses -script example-list-identities
ttrek run -package pure-tcl-aws-ses -script example-send -- from to subject text
```

`./run-example.sh --help` lists arguments. Set AWS credentials and `AWS_REGION`
or `AWS_DEFAULT_REGION` before running AWS examples. The SES `send` example sends
real email when explicitly invoked. Other examples read resources or sign URLs.

## Tests

With Tcl 9.1 and the dependencies on `TCLLIBPATH`:

```sh
make test TCLSH=tclsh9.1
```

Python 3 supplies local HTTP fixtures. Tests use fake credentials and do not
contact AWS. They check requests, result formats, and error handling.

## Install with ttrek

If you do not have the ttrek client, get it from [ttrek.sh](https://ttrek.sh).
Then install the package:

```sh
ttrek install pure-tcl-aws-ses
```
