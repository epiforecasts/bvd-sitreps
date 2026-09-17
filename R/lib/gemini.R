#' One client for the Gemini API.
#'
#' Every call in this repository goes through `gemini()`. That is deliberate:
#' the retry policy, the schema enforcement and the usage log are the parts
#' that make a model call reproducible enough to put a public data artefact
#' on top of, and they only hold if there is one door.
#'
#' Two settings carry most of the weight.
#'
#' `temperature = 0` because this is transcription, not writing. The same PDF
#' should give the same markdown on Tuesday as it did on Monday, and a corpus
#' that drifts between runs cannot be diffed to see what changed upstream.
#'
#' `responseSchema` because the failure mode that matters is not a refusal,
#' it is a plausible-looking table with a column quietly missing. A schema
#' turns that into a parse error at the boundary instead of a wrong CSV three
#' scripts later.
#'
#' Model ids are pinned, not named by family, and were chosen by running the
#' candidates over reports 005 (a province column spanning several rows), 040
#' (grouped indicator tables) and 081 (the dashboard-era layout, whose headers
#' are letter-spaced in the PDF), and comparing their tables cell by cell.
#'
#' On the first prompt, `gemini-3.1-pro-preview` and `gemini-3.8-flash` both
#' scored 1.000 on numeric recall against `pdftools::pdf_text()`, but only pro
#' repeated a spanning province cell on each row (`Ituri|Sous total|16|...`);
#' flash left it empty. The prompt now spells that rule out with an example,
#' and on it flash stopped leaving cells empty. Pro still did better: on 040
#' it kept a province's own totals row (`ITURI|1020|238|23,3%`) where flash
#' folded it into the rows beneath and lost it. Pro is the pin.
#'
#' Cost, 2026-09-17 prices: pro came to $0.28-0.39 a report, about 60% of it
#' thinking tokens, and flash to $0.02-0.06. `gemini-3.1-flash-lite` was a
#' third of flash's cost and dropped a table's worth of figures from 005
#' (recall 0.83), so it would not pass 05-check-corpus.R. The corpus is built
#' once and cached, so pro's cost is paid once per report.
#'
#' Translation only rewrites text it is handed, and every translated table is
#' checked to hold the same numbers as the French, so it runs on flash.
#'
#' `gemini-2.5-pro` and `gemini-2.5-flash` returned 404, and
#' `gemini-3.5-transcribe` rejected this request shape with a 400. Call
#' `gemini_models()` before changing a pin: a retired id fails as a 404 rather
#' than saying it has gone. A preview id is a known risk, and a contained one,
#' because a report already in the corpus is never rebuilt.

GEMINI_ENDPOINT <- "https://generativelanguage.googleapis.com/v1beta/models"

GEMINI_MODEL_TRANSCRIBE <- Sys.getenv("GEMINI_MODEL_TRANSCRIBE",
    unset = "gemini-3.1-pro-preview")
GEMINI_MODEL_TRANSLATE <- Sys.getenv("GEMINI_MODEL_TRANSLATE",
    unset = "gemini-3.8-flash")

GEMINI_ATTEMPTS <- 8
GEMINI_TIMEOUT <- 900

gemini_key <- function() {
    key <- Sys.getenv("GOOGLE_AI_KEY")
    if (!nzchar(key)) {
        stop("GOOGLE_AI_KEY is not set. Put it in ~/.Renviron (local) or in ",
            "the repository's Actions secrets (CI).", call. = FALSE)
    }
    key
}

#' List the models this key can reach.
#'
#' Used at setup to choose what to pin, and worth rerunning when a call starts
#' failing with a 404: a model id that has been retired fails that way rather
#' than saying so.
gemini_models <- function() {
    resp <- httr2::request(GEMINI_ENDPOINT) |>
        httr2::req_url_query(key = gemini_key(), pageSize = 200) |>
        httr2::req_timeout(60) |>
        httr2::req_perform() |>
        httr2::resp_body_json()
    vapply(resp$models, function(m) sub("^models/", "", m$name), character(1))
}

#' What kind of 429 this is.
#'
#' The API returns the same status for four different situations, and they
#' need opposite responses. A per-minute limit clears in seconds and is worth
#' waiting out. A per-day limit clears at midnight Pacific, so retrying burns
#' the next report's attempt for nothing and the run should stop. An exhausted
#' spend cap or prepaid balance will not clear on its own at all. Only the
#' body says which, in the quota ids and the message.
gemini_429_kind <- function(resp) {
    err <- tryCatch(httr2::resp_body_json(resp)$error, error = function(e) NULL)
    if (is.null(err)) return("minute")
    if (grepl("spending cap|prepayment credits|billing details",
        err$message %||% "", ignore.case = TRUE) &&
        !grepl("FreeTier", jsonlite::toJSON(err$details, auto_unbox = TRUE))) {
        return("billing")
    }
    ids <- unlist(lapply(err$details %||% list(), function(d) {
        vapply(d$violations %||% list(), function(v) v$quotaId %||% "", character(1))
    }))
    if (any(grepl("PerDay", ids))) return("daily")
    "minute"
}

#' The wait the API asks for, where it gives one.
gemini_retry_after <- function(resp) {
    err <- tryCatch(httr2::resp_body_json(resp)$error, error = function(e) NULL)
    for (d in err$details %||% list()) {
        if (!is.null(d$retryDelay)) {
            return(as.numeric(sub("s$", "", d$retryDelay)) + 1)
        }
    }
    NA_real_
}

#' Raise a condition a caller can stop a whole run on.
#'
#' Classed so that the loops in 02 and 04 can tell "no more calls today" from
#' "this one report failed", and end the run cleanly in the first case rather
#' than failing every remaining report in turn.
gemini_quota_stop <- function(kind, label, detail = NULL) {
    msg <- switch(kind,
        daily = "Daily request quota reached. It resets at midnight Pacific time; rerun then and cached reports are skipped.",
        billing = "The project behind GOOGLE_AI_KEY has no usable billing (spend cap reached or prepaid credits depleted).",
        budget = paste0("GEMINI_BUDGET_USD reached (", detail, "). Raise it to continue; cached reports are skipped."))
    structure(
        class = c("gemini_quota_stop", "error", "condition"),
        list(message = paste0(msg, if (!is.na(label)) paste0(" (at ", label, ")") else ""),
            call = NULL, kind = kind)
    )
}

#' A single generateContent call returning parsed JSON.
#'
#' `parts` is the request's content parts, built by the callers below. The
#' retry covers per-minute 429s and 5xx, which are the transient ones, and
#' waits as long as the API asks. A daily or billing 429 is not retried and
#' raises `gemini_quota_stop`. A 400 is a bad request and retrying it just
#' wastes quota, so it is allowed to fail.
gemini <- function(parts, schema, model = GEMINI_MODEL_TRANSCRIBE,
                   temperature = 0, label = NA_character_,
                   thinking_level = NULL) {
    gemini_check_budget(model, label)

    body <- list(
        contents = list(list(role = "user", parts = parts)),
        generationConfig = list(
            temperature = temperature,
            responseMimeType = "application/json",
            responseSchema = schema
        )
    )
    # Left to the model's default unless set. SitRep 008 thought for 62,914
    # tokens on pro, filled the 65,536-token output limit and returned 2,608
    # tokens of transcription, the same way on a rerun; "low" is for reports
    # like that, not a general saving.
    if (!is.null(thinking_level)) {
        body$generationConfig$thinkingConfig <- list(thinkingLevel = thinking_level)
    }

    req <- httr2::request(paste0(GEMINI_ENDPOINT, "/", model, ":generateContent")) |>
        httr2::req_url_query(key = gemini_key()) |>
        httr2::req_body_json(body, auto_unbox = TRUE) |>
        httr2::req_timeout(GEMINI_TIMEOUT) |>
        httr2::req_retry(
            max_tries = GEMINI_ATTEMPTS,
            is_transient = function(r) {
                s <- httr2::resp_status(r)
                if (s == 429) return(gemini_429_kind(r) == "minute")
                s %in% c(500, 502, 503, 504)
            },
            after = gemini_retry_after,
            backoff = function(i) min(60, 5 * 2^(i - 1)),
            # A dropped connection is not a response, so is_transient never
            # sees it. Without this, a network blip failed two reports in a
            # row twice in the first full build.
            retry_on_failure = TRUE
        )

    resp <- tryCatch(
        httr2::req_perform(req),
        httr2_http_429 = function(e) {
            kind <- gemini_429_kind(e$resp)
            if (kind %in% c("daily", "billing")) stop(gemini_quota_stop(kind, label))
            stop(e)
        }
    ) |>
        httr2::resp_body_json(simplifyVector = FALSE)

    # Logged before any check below can fail: a call that stops on the output
    # limit is still billed, and leaving it out of the ledger would let the
    # budget stop undercount.
    gemini_log_usage(label, model, resp$usageMetadata)

    cand <- resp$candidates[[1]]
    reason <- cand$finishReason
    if (!is.null(reason) && !reason %in% c("STOP", "MAX_TOKENS")) {
        stop("Gemini stopped with finishReason ", reason,
            if (!is.na(label)) paste0(" on ", label) else "", call. = FALSE)
    }
    if (!is.null(reason) && reason == "MAX_TOKENS") {
        stop("Gemini hit the output token limit",
            if (!is.na(label)) paste0(" on ", label) else "",
            " (", resp$usageMetadata$candidatesTokenCount %||% "?", " output, ",
            resp$usageMetadata$thoughtsTokenCount %||% "?", " thinking tokens).",
            " Usually a repetition loop or runaway thinking rather than a long",
            " document; a rerun often succeeds.", call. = FALSE)
    }

    txt <- paste(vapply(cand$content$parts, function(p) p$text %||% "",
        character(1)), collapse = "")
    parsed <- tryCatch(
        jsonlite::fromJSON(txt, simplifyVector = FALSE),
        error = function(e) stop("Gemini returned unparseable JSON",
            if (!is.na(label)) paste0(" on ", label) else "", ": ",
            conditionMessage(e), call. = FALSE)
    )

    parsed
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# ----------------------------------------------------------------- spend ----

#' Standard paid-tier prices, USD per million tokens, from
#' https://ai.google.dev/gemini-api/docs/pricing on 2026-09-17. Thinking tokens
#' are billed at the output rate. Prompts over 200k tokens cost more on pro;
#' no report comes near that. Update this table when changing a pin, or the
#' budget stop below will price calls wrongly.
GEMINI_PRICES <- list(
    "gemini-3.1-pro-preview" = c(input = 2.00, output = 12.00),
    "gemini-3.8-flash" = c(input = 0.75, output = 3.75),
    "gemini-3.5-flash-lite" = c(input = 0.30, output = 2.50),
    "gemini-3.1-flash-lite" = c(input = 0.25, output = 1.50),
    "gemini-2.5-flash-lite" = c(input = 0.10, output = 0.40)
)

#' `GEMINI_LEDGER` can point several repositories at one ledger, so that a
#' single `GEMINI_BUDGET_USD` covers everything spent on one key.
gemini_ledger_path <- function() {
    Sys.getenv("GEMINI_LEDGER", unset = here::here("outputs", "gemini-ledger.csv"))
}

#' The last four characters of the key, to attribute spend to a project.
#'
#' Spend is budgeted per key because each key's project is billed separately,
#' and a budget for this key should not count calls made on another.
gemini_key_tail <- function() {
    k <- gemini_key()
    substr(k, nchar(k) - 3L, nchar(k))
}

gemini_cost <- function(model, input_tokens, billed_output_tokens) {
    p <- GEMINI_PRICES[[model]]
    if (is.null(p)) return(NA_real_)
    (input_tokens * p[["input"]] + billed_output_tokens * p[["output"]]) / 1e6
}

#' USD spent so far on the current key, estimated from the ledger.
gemini_spent <- function() {
    path <- gemini_ledger_path()
    if (!file.exists(path)) return(0)
    led <- data.table::fread(path, colClasses = list(character = "key_tail"))
    sum(led[key_tail == gemini_key_tail()]$cost_usd, na.rm = TRUE)
}

#' Stop before a call if the budget for this key is used up.
#'
#' `GEMINI_BUDGET_USD` caps spend on the current key, estimated from token
#' counts and the price table. It is checked before each call, so a run can
#' overshoot by at most one call. A prepaid project also has Google's own hard
#' stop when credit runs out, which arrives as a "billing" 429 and stops the
#' run the same way; this check is for stopping short of that, so that some
#' budget is kept back.
gemini_check_budget <- function(model, label) {
    budget <- suppressWarnings(as.numeric(Sys.getenv("GEMINI_BUDGET_USD")))
    if (is.na(budget)) return(invisible(TRUE))
    if (is.null(GEMINI_PRICES[[model]])) {
        stop("No price for ", model, " in GEMINI_PRICES, so a budget cannot ",
            "be enforced. Add it before running with GEMINI_BUDGET_USD set.",
            call. = FALSE)
    }
    spent <- gemini_spent()
    if (spent >= budget) {
        stop(gemini_quota_stop("budget", label,
            sprintf("$%.2f of $%.2f", spent, budget)))
    }
    invisible(TRUE)
}

#' Append one row per call to outputs/gemini-ledger.csv.
#'
#' Token counts are the only honest way to answer "what did rebuilding the
#' corpus cost", and they are gone once the response is discarded. Thinking
#' tokens are recorded separately because they are billed as output but are
#' not in `candidatesTokenCount`; on pro they were twice the transcription.
gemini_log_usage <- function(label, model, usage) {
    if (is.null(usage)) return(invisible(NULL))
    input <- usage$promptTokenCount %||% 0
    output <- usage$candidatesTokenCount %||% 0
    thinking <- usage$thoughtsTokenCount %||% 0
    row <- data.frame(
        time = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        key_tail = gemini_key_tail(),
        label = label,
        model = model,
        input_tokens = input,
        output_tokens = output,
        thinking_tokens = thinking,
        cost_usd = round(gemini_cost(model, input, output + thinking), 6)
    )
    path <- gemini_ledger_path()
    dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
    data.table::fwrite(row, path, append = file.exists(path))
    invisible(NULL)
}

#' A PDF as a request part.
#'
#' Inline base64 rather than the Files API: the reports are a few megabytes,
#' which is well inside the inline limit, and it keeps the call stateless so a
#' failure leaves nothing to clean up on Google's side.
gemini_pdf_part <- function(path) {
    list(inline_data = list(
        mime_type = "application/pdf",
        data = base64enc::base64encode(path)
    ))
}

gemini_text_part <- function(text) list(text = text)
