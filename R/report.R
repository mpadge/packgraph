#' pg_report
#'
#' Report on package structure
#'
#' @param g A package graph objected returned from \link{pg_graph}
#' @return Summary report on package structure
#' @export
pg_report <- function (g) {

    if (missing (g))
        stop ("g must be supplied")

    g$nodes$centrality [g$nodes$centrality == 0] <- NA

    pkgstats <- get_pkg_stats (g)

    cli_out (pkgstats)

    invisible (md_out (g, pkgstats))
}

pkg_name <- function (pkg_dir) {

    desc <- readLines (file.path (pkg_dir, "DESCRIPTION"))
    gsub ("Package:\\s?", "", desc [grep ("^Package\\:", desc)])
}

get_pkg_stats <- function (g) {

    g$nodes$loc <- g$nodes$line2 - g$nodes$line1 + 1

    pkgstats <- list (pkgname = attr (g, "pkg_name"))
    pkgstats$non_exports <- g$nodes [!g$nodes$export, ]
    pkgstats$exports <- g$nodes [g$nodes$export, ]

    group_table <- table (g$nodes$group)

    cluster_groups <- names (group_table) [which (group_table > 1)] %>%
        as.integer ()
    isolated_groups <- names (group_table) [which (group_table == 1)] %>%
        as.integer ()
    clusters <- g$nodes [which (g$nodes$group %in% cluster_groups), ]

    pkgstats$isolated <- g$nodes [which (g$nodes$group %in% isolated_groups),
                                  "name",
                                  drop = TRUE]

    # base-r way of grouping and ordering
    pkgstats$clusters <- lapply (split (clusters, f = factor (clusters$group)),
                                 function (i)
                                 i [order (i$centrality, decreasing = TRUE), ])
    pkgstats$cluster_sizes <- vapply (pkgstats$clusters,
                                      function (i) nrow (i),
                                      integer (1), USE.NAMES = FALSE)

    pkgstats$num_clusters <- length (pkgstats$clusters)
    pkgstats$num_isolated <- length (pkgstats$isolated)

    return (pkgstats)
}

list_collapse <- function (x) {
    if (length (x) > 1)
        x <- paste0 (paste0 (x [-length (x)],
                             collapse = ", "),
                     " and ", x [length (x)])
    return (x)
}


# screen output via cli
cli_out <- function (pkgstats) {

    message (cli::rule (line = 2, left = pkgstats$pkgname, col = "green"))
    cli::cli_text ("")

    cli::cli_text (cli::col_blue (clusters_out (pkgstats, md = FALSE)))

    cl <- lapply (clusters_list (pkgstats, md = FALSE), function (i)
                  print (knitr::kable (i)))
    cli::cli_text ("")

    if (pkgstats$num_isolated > 0) {

        res <- isolated_out (pkgstats, md = FALSE)
        cli::cli_text (res$txt)
        print (knitr::kable (res$iso_fns))
    }
    cli::cli_text ("")

    dl <- doclines_out (pkgstats, exports = TRUE)
    #cli::cli_text (dl$txt)
    message (dl$txt)
    print (knitr::kable (dl$vals))
    message ()

    dl <- doclines_out (pkgstats, exports = FALSE)
    #cli::cli_text (dl$txt)
    message (dl$txt)
    print (knitr::kable (dl$vals))

    out <- central_node_docs (pkgstats)
    if (length (out) > 1) {

        cli::cli_text ("")
        cli::cli_text (out)
    }
}

md_out <- function (g, pkgstats) {

    out <- c (paste0 ("## ", pkgstats$pkgname), "")

    out <- c (out, clusters_out (pkgstats, md = TRUE), "")

    for (i in clusters_list (pkgstats, md = TRUE))
        out <- c (out, knitr::kable (i, format = "markdown"), "")

    if (pkgstats$num_isolated > 0) {

        res <- isolated_out (pkgstats, md = TRUE)
        out <- c (out, res$txt, knitr::kable (res$iso_fns, format = "markdown"))
    }

    out <- c (out, "")

    dl <- doclines_out (pkgstats, md = TRUE, exports = TRUE)
    out <- c (out, dl$txt, knitr::kable (dl$vals, format = "markdown"))

    dl <- doclines_out (pkgstats, md = TRUE, exports = FALSE)
    out <- c (out, dl$txt, knitr::kable (dl$vals, format = "markdown"))

    out <- c (out, central_node_docs (pkgstats))

    return (out)
}

# Summary output of numbers and sizes of clusters
clusters_out <- function (pkgstats, md = FALSE) {

    cs <- paste0 (pkgstats$cluster_sizes)
    # if multiple clusters, or single cluster and multiple functions:
    cluster_fn_fmt <- ifelse ((length (pkgstats$cluster_sizes) > 1 |
                               (length (pkgstats$cluster_sizes) == 1 &
                                pkgstats$cluster_sizes [1] > 1)), "s", "")
    paste0 ("The ", pkgstats$pkg_name, " package has ",
            nrow (pkgstats$exports), " exported functions, and ",
            nrow (pkgstats$non_exports),
            " non-exported funtions. The exported functions are ",
            "structured into the following ",
            pkgstats$num_clusters, " primary cluster",
            ifelse (pkgstats$num_clusters > 1, "s", ""),
            " containing ", list_collapse (cs),
            " function", cluster_fn_fmt)
}

# Summary output of cluster memberships
clusters_list <- function (pkgstats, md = FALSE) {

    out <- list ()
    for (i in seq (pkgstats$clusters)) {

        out [[i]] <- data.frame (
                cluster = i,
                 n = seq (nrow (pkgstats$clusters [[i]])),
                 name = pkgstats$clusters [[i]]$name,
                 exported = pkgstats$clusters [[i]]$export,
                 num_params = pkgstats$clusters [[i]]$num_params,
                 num_doc_words = pkgstats$clusters [[i]]$n_doc_words,
                 num_doc_lines = pkgstats$clusters [[i]]$doc_lines,
                 num_example_lines = pkgstats$clusters [[i]]$n_example_lines,
                 centrality = pkgstats$clusters [[i]]$centrality,
                 row.names = NULL)
}

return (out)
}

# Summary output of isolated functions
isolated_out <- function (pkgstats, md = FALSE) {

    nmtxt <- ifelse (pkgstats$num_isolated > 1, "are", "is")
    out_txt <- paste0 ("There ", nmtxt, " also ", pkgstats$num_isolated,
                       " isolated function",
                       ifelse (pkgstats$num_isolated > 1, "s", ""), ":")
    allfns <- rbind (pkgstats$exports, pkgstats$non_exports)
    iso_fns <- data.frame (n = seq (pkgstats$num_isolated),
                           name = pkgstats$isolated,
                           loc = allfns$loc [match (pkgstats$isolated,
                                                    allfns$name)],
                           row.names = NULL)
    list (txt = out_txt, iso_fns = iso_fns)
}

doclines_out <- function (pkgstats, md = FALSE, exports = TRUE) {

    type <- ifelse (exports, "exports", "non_exports")
    stats <- pkgstats [[type]]

    type <- ifelse (exports, "exported", "non-exported")
    txt <- paste0 ("Summary of ",
                   nrow (stats),
                   " ",
                   type,
                   " functions")

    if (md)
        txt <- c (paste0 ("### ", txt, ":"), "")
    else
        txt <- cli::rule (line = 1, left = txt)

    fn_lines <- stats$line2 - stats$line1 + 1

    vals <- data.frame (value = c ("mean", "median"),
                num_params = c (round (mean (stats$num_params), digits = 1),
                                stats::median (stats$num_params)),
                num_lines = c (round (mean (fn_lines), digits = 1),
                               stats::median (fn_lines)),
                doclines = c (round (mean (stats$doc_lines), digits = 1),
                              stats::median (stats$doc_lines)),
                cmtlines = c (round (mean (stats$cmt_lines), digits = 1),
                              stats::median (stats$cmt_lines)))

    list (txt = txt, vals = vals)
}

central_node_docs <- function (pkgstats) {

    n <- pkgstats$exports
    n <- n [which (n$centrality > 0), ]
    out <- ""

    # only analyse if > 4 fns have non-zero centrality measures
    if (nrow (n) > 4) {

        r2_doc_all <- stats::cor (n$centrality, n$doc_lines)
        r2_ex <- stats::cor (n$centrality, n$n_example_lines)
        r2_doc_no_ex <- stats::cor (n$centrality,
                                    n$doc_lines - n$n_example_lines)

        if (r2_doc_all < 0)
            out <- c (out, paste0 ("More central functions should be ",
                                   "better documented than less central ",
                                   "functions, yet this is not the case here"))
        if (r2_ex < 0)
            out <- c (out, paste0 ("More central functions should have ",
                                   "more extensive examples than less central ",
                                   "functions, yet this is not the case here"))
    }

    return (out)
}
