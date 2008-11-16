
#include <lighttpd/base.h>
#include <lighttpd/http_request_parser.h>

/** Machine **/

#define _getString(M, FPC) (chunk_extract(vr, ctx->M, GETMARK(FPC)))
#define getString(FPC) _getString(mark, FPC)

#define _getStringTo(M, FPC, s) (chunk_extract_to(vr, ctx->M, GETMARK(FPC), s))
#define getStringTo(FPC, s) _getStringTo(mark, FPC, s)


%%{

	machine http_request_parser;
	variable cs ctx->chunk_ctx.cs;

	action mark { ctx->mark = GETMARK(fpc); }
	action done { fbreak; }

	action method { getStringTo(fpc, ctx->request->http_method_str); }
	action uri { getStringTo(fpc, ctx->request->uri.raw); }

	action header_key {
		getStringTo(fpc, ctx->h_key);
		g_string_truncate(ctx->h_value, 0);
	}
	action header_value {
		getStringTo(fpc, ctx->h_value);
	}
	action header {
		http_header_insert(ctx->request->headers, GSTR_LEN(ctx->h_key), GSTR_LEN(ctx->h_value));
	}

# RFC 2616
	OCTET = any;
	CHAR = ascii;
	UPALPHA = upper;
	LOALPHA = lower;
	ALPHA = alpha;
	DIGIT = digit;
	CTL = ( 0 .. 31 | 127 );
	CR = '\r';
	LF = '\n';
	SP = ' ';
	HT = '\t';
	DQUOTE = '"';

	CRLF = CR LF;
	LWS = CRLF? (SP | HT)+; # linear white space
	TEXT = (OCTET - CTL) | LWS;
	HEX = [a-fA-F0-9];

	Separators = [()<>@,;:\\\"/\[\]?={}] | SP | HT;
	Token = (OCTET - Separators - CTL)+;

	# original definition
	# Comment = "(" ( CText | Quoted_Pair | Comment )* ")";
	# CText   = TEXT - [()];

	Quoted_Pair    = "\\" CHAR;
	Comment        = ( TEXT | Quoted_Pair )*;
	QDText         = TEXT - DQUOTE;
	Quoted_String   = DQUOTE ( QDText | Quoted_Pair )* DQUOTE;

	HTTP_Version = (
		  "HTTP/1.0"  %{ ctx->request->http_version = HTTP_VERSION_1_0; }
		| "HTTP/1.1"  %{ ctx->request->http_version = HTTP_VERSION_1_1; }
		| "HTTP" "/" DIGIT+ "." DIGIT+ ) >{ ctx->request->http_version = HTTP_VERSION_UNSET; };
	#HTTP_URL = "http:" "//" Host ( ":" Port )? ( abs_path ( "?" query )? )?;

# RFC 2396

	Mark = [\-_!~*\'()];
	Unreserved = alnum | Mark;
	Escaped = "%" HEX HEX;

	PChar = Unreserved | Escaped | [:@&=+$,];
	Segment = PChar* ( ";" PChar* )*;
	Path_Segments = Segment ("/" Segment)*;
	Abs_Path = "/" Path_Segments;

	Method = (
		  "GET"       %{ ctx->request->http_method = HTTP_METHOD_GET; }
		| "POST"      %{ ctx->request->http_method = HTTP_METHOD_POST; }
		| "HEAD"      %{ ctx->request->http_method = HTTP_METHOD_HEAD; }
		| "OPTIONS"   %{ ctx->request->http_method = HTTP_METHOD_OPTIONS; }
		| "PROPFIND"  %{ ctx->request->http_method = HTTP_METHOD_PROPFIND; }
		| "MKCOL"     %{ ctx->request->http_method = HTTP_METHOD_MKCOL; }
		| "PUT"       %{ ctx->request->http_method = HTTP_METHOD_PUT; }
		| "DELETE"    %{ ctx->request->http_method = HTTP_METHOD_DELETE; }
		| "COPY"      %{ ctx->request->http_method = HTTP_METHOD_COPY; }
		| "MOVE"      %{ ctx->request->http_method = HTTP_METHOD_MOVE; }
		| "PROPPATCH" %{ ctx->request->http_method = HTTP_METHOD_PROPPATCH; }
		| "REPORT"    %{ ctx->request->http_method = HTTP_METHOD_REPORT; }
		| "CHKECOUT"  %{ ctx->request->http_method = HTTP_METHOD_CHECKOUT; }
		| "CHECKIN"   %{ ctx->request->http_method = HTTP_METHOD_CHECKIN; }
		| "VERSION-CONTROL" %{ ctx->request->http_method = HTTP_METHOD_VERSION_CONTROL; }
		| "UNCHECKOUT"      %{ ctx->request->http_method = HTTP_METHOD_UNCHECKOUT; }
		| "MKACTIVITY"      %{ ctx->request->http_method = HTTP_METHOD_MKACTIVITY; }
		| "MERGE"     %{ ctx->request->http_method = HTTP_METHOD_MERGE; }
		| "LOCK"      %{ ctx->request->http_method = HTTP_METHOD_LOCK; }
		| "UNLOCK"    %{ ctx->request->http_method = HTTP_METHOD_UNLOCK; }
		| "LABEL"     %{ ctx->request->http_method = HTTP_METHOD_LABEL; }
		| "CONNECT"   %{ ctx->request->http_method = HTTP_METHOD_CONNECT; }
		| Token ) >mark >{ ctx->request->http_method = HTTP_METHOD_UNSET; } %method;

	Request_URI = ("*" | ( any - CTL - SP )+) >mark %uri;
	Request_Line = Method " " Request_URI " " HTTP_Version CRLF;

	Field_Content = ( TEXT+ | ( Token | Separators | Quoted_String )+ );
	Field_Value = " "* (Field_Content+ ( Field_Content | LWS )*)? >mark %header_value;
	Message_Header = Token >mark %header_key ":" Field_Value? % header;

	main := (CRLF)* Request_Line (Message_Header CRLF)* CRLF @ done;
}%%

%% write data;

static int http_request_parser_has_error(http_request_ctx *ctx) {
	return ctx->chunk_ctx.cs == http_request_parser_error;
}

static int http_request_parser_is_finished(http_request_ctx *ctx) {
	return ctx->chunk_ctx.cs >= http_request_parser_first_final;
}

void http_request_parser_init(http_request_ctx* ctx, request *req, chunkqueue *cq) {
	chunk_parser_init(&ctx->chunk_ctx, cq);
	ctx->request = req;
	ctx->h_key = g_string_sized_new(0);
	ctx->h_value = g_string_sized_new(0);

	%% write init;
}

void http_request_parser_reset(http_request_ctx* ctx) {
	chunk_parser_reset(&ctx->chunk_ctx);
	g_string_truncate(ctx->h_key, 0);
	g_string_truncate(ctx->h_value, 0);

	%% write init;
}

void http_request_parser_clear(http_request_ctx *ctx) {
	g_string_free(ctx->h_key, TRUE);
	g_string_free(ctx->h_value, TRUE);
}

handler_t http_request_parse(vrequest *vr, http_request_ctx *ctx) {
	handler_t res;

	if (http_request_parser_is_finished(ctx)) return HANDLER_GO_ON;

	if (HANDLER_GO_ON != (res = chunk_parser_prepare(&ctx->chunk_ctx))) return res;

	while (!http_request_parser_has_error(ctx) && !http_request_parser_is_finished(ctx)) {
		char *p, *pe;

		if (HANDLER_GO_ON != (res = chunk_parser_next(vr, &ctx->chunk_ctx, &p, &pe))) return res;

		%% write exec;

		chunk_parser_done(&ctx->chunk_ctx, p - ctx->chunk_ctx.buf);
	}

	if (http_request_parser_has_error(ctx)) return HANDLER_ERROR;
	if (http_request_parser_is_finished(ctx)) {
		chunkqueue_skip(ctx->chunk_ctx.cq, ctx->chunk_ctx.bytes_in);
		return HANDLER_GO_ON;
	}
	return HANDLER_ERROR;
}
