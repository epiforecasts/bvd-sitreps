#' Talking to insp.cd.
#'
#' Three things about the site drive everything here. It returns HTTP 403 to
#' default user agents, so every request carries a browser one; without it an
#' empty answer cannot be told from a refused one. It answers slowly under
#' load, 15-20 seconds being normal mid-outbreak, so the timeout is generous
#' and retries are spaced rather than eager. And it is a small institution's
#' server carrying an outbreak response, so requests are sequential and the
#' page size is large: fewer, bigger calls rather than many small ones.

INSP_UA <- paste0(
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ",
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
)

INSP_TIMEOUT <- 180
INSP_ATTEMPTS <- 5
INSP_BACKOFF <- 5

#' A GET with the user agent, timeout and retry policy the site needs.
#'
#' `req_retry` is given an explicit backoff rather than the default jittered
#' one so that a struggling server gets a predictable five seconds of quiet
#' between attempts instead of an occasional immediate retry.
insp_get <- function(url, query = NULL) {
    req <- httr2::request(url) |>
        httr2::req_user_agent(INSP_UA) |>
        httr2::req_timeout(INSP_TIMEOUT) |>
        httr2::req_retry(
            max_tries = INSP_ATTEMPTS,
            backoff = function(i) INSP_BACKOFF * i
        )
    if (!is.null(query)) req <- httr2::req_url_query(req, !!!query)
    httr2::req_perform(req)
}

insp_get_json <- function(url, query = NULL) {
    httr2::resp_body_json(insp_get(url, query))
}

#' Download a file, writing to a temporary path first.
#'
#' A half-written PDF that keeps the name of a complete one is worse than no
#' PDF at all: the next run sees the file, skips it, and the corruption is
#' only found much later by whatever tries to read it. Renaming into place
#' after the body is on disk makes the file's existence mean it is whole.
insp_download <- function(url, dest) {
    tmp <- paste0(dest, ".part")
    on.exit(unlink(tmp), add = TRUE)
    resp <- insp_get(url)
    writeBin(httr2::resp_body_raw(resp), tmp)
    if (file.size(tmp) == 0) {
        stop("Empty body downloading ", url, call. = FALSE)
    }
    file.rename(tmp, dest)
    invisible(dest)
}
