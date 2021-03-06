###########################################################################
# Author:   Patrick Rockenschaub
# Project:  Preserve Antibiotics through Safe Stewardship (PASS)
#           Primary Care work package 1
#           Gharbi et al. re-analysis
#
# File:     03_base_analysis.R
# Date:     21/09/2020
# Task:     A non-markdown copy of 03_base_analysis.Rmd
#
###########################################################################

# ```{r init, include = FALSE}

# Initialise the workspace
source(file.path("00_init.R"))
source(file.path("00_tabulation.R"))

# Infrastructure packages
library(knitr)
library(kableExtra)
library(broom)
library(forcats)
library(ggplot2)
library(tableone)

# Analysis packages
library(geepack)

# Shorten parameters
time_window <- 60
bootstrap_nneh <- 10
format <- "markdown"

# ```

# ```{r load-data}

epi <- load_derived(str_c("epi_", time_window))
setDT(epi)
setorder(epi, patid, start)

# ```

# ```{r recode-cci}

epi[, cci_bin := factor(cci > 0, c(FALSE, TRUE), c("0", "1+"))]

# ```

# ```{r recode-years}

# CHANGE June 6th 2020: 
# This change in coding the year was made in response to a request by reviewer #1
epi[, year := fct_relevel(year, "2007", "2008", "2009")]

# ```

# ```{r summ-measures}

# Episodes
mean(epi$age)

sum(epi$female == "yes")
mean(epi$female == "yes")

# ```



# ```{r table-1}

covar <- c("age", "age_cat", "female", "imd", "region", "year",
           "cci", "cci_bin", "smoke", "recur",
           "hosp_7", "hosp_30", "hosp_nights", "hosp_n",
           "ae_30", "ae_n", "abx_7", "abx_30", "home",
           "sep", "tts", "other_hosp", "died")

nonnormal <- c("age", "cci", "hosp_nights", "hosp_n", "ae_n", "tts")

total <- CreateTableOne(covar, data = epi)
strat <- CreateTableOne(covar, strata = "presc", data = epi)


list(
  print(total, dropEqual = TRUE, printToggle = FALSE, nonnormal = nonnormal), 
  print(strat, dropEqual = TRUE, printToggle = FALSE, nonnormal = nonnormal, test = FALSE),
  print(strat, dropEqual = TRUE, printToggle = FALSE, nonnormal = nonnormal)[, "p", drop = FALSE]
) %>% 
  reduce(cbind) %>%
  as.data.table(keep.rownames = "var")

# ```


# ```{r time-to-sepsis}

median(epi[presc == "no" & !is.na(tts)]$tts)
quantile(epi[presc == "no" & !is.na(tts)]$tts, c(0.25, 0.75))

median(epi[presc == "no" & !is.na(tts)]$tts)
quantile(epi[presc == "no" & !is.na(tts)]$tts, c(0.25, 0.75))

# ```


# ```{r tab_rate}

crude_gee <- function(mod, var){
  # Extract crude fixed effects from a fitted GEE model
  #
  # Args:
  #   mod - fitted geeglm model
  #   var - name of the variable for which to extract effects
  #
  # Result:
  #   data.table with variable names, levels, effect and 95%-CI
  
  coefs <- tidy(mod) %>% as.data.table()
  x <- mod$data[[var]]
  
  if(is.factor(x)){
    lvls <- levels(x)
    ref <- 
      data.table(variable = var, value = lvls[1], effect = 1, lower = NA, upper = NA)
  } else {
    ref <- NULL
  }
  
  eff <- 
    coefs[
      str_detect(term, var) & !str_detect(term, ":"), c(
        .(variable = var, value = str_replace(term, var, ""), effect = exp(estimate)), 
        norm_ci(estimate, std.error)
      )]
  
  rbind(ref, eff)
}

p_val <- function(mod, var){
  # Extract the p.value from a glmmTMB model
  #
  # Args:
  #   mod - fitted glmmTMB model (not zero-inflated)
  #   var - name of the variable for which to extract the p.values
  #
  # Result:
  #   data.table
  
  coefs <- tidy(mod) %>% as.data.table()
  
  coefs %<>% .[str_detect(term, var), .(variable = var, 
                                        value = str_replace(term, var, ""), 
                                        p.value)]
  coefs[]
}

tab_odds <- function(dt, outcome, var, group){
  # Calculate the crude relative odds of an outcome stratified by `var`. 
  # This function ignores the `group` parameter (only included for compatibility 
  # with the tabulation functions)
  #
  # Args:
  #   dt - data.table on which to calculate rates (must include column `num_abx`)
  #   outcome - name of the outcome variable
  #   var - name of the variable to stratify by
  #   group - ignored
  #
  # Result:
  #   a data.table with all levels of `var` in a var column and columns `rate`
  #   (absolute rate) and `ratio` (relative rate)
  
  
  mod <- geeglm(as.formula(str_c(outcome, "~", var)), id = patid, wave = nmr,
                data = dt, family = binomial, corstr = "exchangeable")
  
  est_cols <- c("effect", "lower", "upper")
  to_string <- substitute(str_c(effect, " (", lower, "-", upper, ")"))
  
  summ <- 
    list(or = crude_gee, p.value = p_val) %>% 
    invoke_map(.x = list(list(mod = mod, var = var)))
  
  summ$or[, (est_cols) := map(.SD, prty, 2), .SDcols = est_cols]
  summ$or[, or := eval(to_string)]
  
  summ$p.value[, p.value := if_else(p.value < 0.001, "<0.001", prty(p.value, 3))] 
  
  summ %<>% reduce(merge, by = c("variable", "value"))
  
  summ[, .(var = value, .all = "all", or, p.value)]
}

# ```

# ```{r plot-age-sep}

age_sep <- epi[, .(age, sep, decile = ntile(age, n = 10))] %>% 
  .[, .(age = mean(age), sep = mean(sep == "yes")), by = decile]

ggplot(age_sep, aes(age, sep * 1000)) + 
  geom_point() + 
  geom_smooth(method = "lm", se = FALSE) + 
  scale_y_continuous(limits = c(0, NA)) + 
  labs(x = "\n\nAge deciles", y = "Number of sepsis cases per 1,000 patients\n\n") + 
  theme_minimal()

# ```

# ```{r recode-age}
# Re-center and rescale the main continuous variables
age_ref <- 75
age_scl <- 5
epi[, age := .((age - age_ref) / age_scl)]

# ```

# ```{r transform-skew}

# Since all skewed variables contain 0 entries, square root instead of 
# the logarithm is used to model diminishing effects. This is also 
# supported by IC measures
epi[, cci_sqrt := sqrt(cci)]
epi[, hosp_n_sqrt := sqrt(hosp_n)]
epi[, hosp_nights_sqrt := sqrt(hosp_nights)]
epi[, ae_n_sqrt := sqrt(ae_n)]

# ```

# ```{r table-shell}

# Load the table shell
tbl_shell <- read_csv(file.path("table_2_shell.csv"), col_types = "ccc")
setDT(tbl_shell)

add_shell_headers <- function(rend, shell){
  # Add the category headers based on the table shell instead of the list
  # definition that was used above
  
  headers <- unique(shell[!is.na(header)]$header)
  for(h in headers){
    ids <- which(shell$header == h)
    rend %<>% group_rows(h, min(ids), max(ids)) 
  }
  rend
}

render <- function(table, columns = 1, header = NULL, caption = ""){
  
  render <- 
    table %>% 
    kable(
      format, 
      booktabs = TRUE,
      linesep = "",
      escape = FALSE,
      col.names = c("Patient characteristics", rep(c("OR (95%-CI)", "p-value"), columns)),
      caption = caption
    ) 
  
  if(format != "markdown"){
    render %<>%  
      kable_styling() %>% 
      add_shell_headers(tbl_shell)
    
    if(!is.null(header)){
      render %<>% add_header_above(header)
    }
    
  }
  
  render
}

# ```

# ```{r model-definition}

fit_model <- function(formula, data){
  # Fit a GEE logistic regression of a certain form (formula) to some data (data). 
  # This is mostly a convenience function to fit models with and without interactions.
  
  fit <- geeglm(formula, id = patid, family = binomial, data = data, corstr = "exchangeable")
  fit
}

summarise_model <- function(model){
  # Extract the coefficients, 95% confidence intervals and p-values 
  # from a fitted model
  
  coefs <- tidy(model)
  setDT(coefs)
  
  coefs[, est := prty(exp(estimate), 2)]
  coefs[, lower := prty(exp(estimate + qnorm(0.025) * std.error), 2)]
  coefs[, upper := prty(exp(estimate + qnorm(0.975) * std.error), 2)]
  coefs[, or := str_c(est, " (", lower, "-", upper, ")")]
  coefs[, p.value := if_else(p.value < 0.001, "<0.001", prty(p.value, 3))]
  
  coefs %<>% .[tbl_shell, on = .(term)]
  coefs[, .(var, or, p.value)]
}

fit_and_summarise <- function(formula, data){
  # Wrapper function to fit a model and simultaneously summarise it
  
  model <- fit_model(formula, data)
  list(model = model, summary = summarise_model(model))
}

# ```


# ```{r define-table-2}


table_2 <- function(dt, tab_fun){
  tbl_parms <- list(aux = c("patid", "sep", "died", "other_hosp", "nmr"), cast = c("or", "p.value"))
  
  tbl_def <- list(
    "No antibiotic" = tab(presc ~ ., fun = tab_fun, tbl_parms, keep_only = "no"),
    "Age (cont.)" = tab(age ~ ., fun = tab_fun, tbl_parms),
    "Female" = tab(female ~ ., fun = tab_fun, tbl_parms, keep_only = "yes"),
    "IMD" = tab(imd ~ ., fun = tab_fun, tbl_parms),
    "Region" = tab(region ~ ., fun = tab_fun, tbl_parms),
    "Financial year" = tab(year ~ ., fun = tab_fun, tbl_parms),
    "CCI (cont.)" = tab(cci_sqrt ~ ., fun = tab_fun, tbl_parms),
    "Smoking status" = tab(smoke ~ ., fun = tab_fun, tbl_parms),
    "Recurrent UTI" = tab(recur ~ ., fun = tab_fun, tbl_parms),
    
    "Inpatient admission" = list(
      "IP prior 7 days" = tab(hosp_7 ~ ., fun = tab_fun, tbl_parms, keep_only = "yes"),
      "IP prior 30 days" = tab(hosp_30 ~ ., fun = tab_fun, tbl_parms, keep_only = "yes"),
      "IP nights last year" = tab(hosp_nights_sqrt ~ ., fun = tab_fun, tbl_parms),
      "hospitalisations last year" = tab(hosp_n_sqrt ~ ., fun = tab_fun, tbl_parms)
    ),
    
    "Accidents & Emergencies" = list(
      "A&E prior 30 days" = tab(ae_30 ~ ., fun = tab_fun, tbl_parms),
      "attendances last year" = tab(ae_n_sqrt ~ ., fun = tab_fun, tbl_parms)
    ),
    
    "Antibiotics in prior 30 days" = tab(abx_30 ~ ., fun = tab_fun, tbl_parms, keep_only = "yes"),
    "Index event was home visit" = tab(home ~ ., fun = tab_sep_odds, tbl_parms, keep_only = "yes")
  )
  
  if(length(unique(dt$female)) == 1){
    # For stratified analysis
    tbl_def["Female"] <- NULL
  }
  
  tbl_def %>% render_tab(dt)
}


# ```


# ```{r table-2}

# Calculate the table using functions from 00_tabulation.R
tab_sep_odds <- partial(tab_odds, outcome = "sep == 'yes'")
tbl_2 <- table_2(epi, tab_sep_odds)

# Run a fully adjusted model with gender interaction 
covars <- c("age", "imd", "region", "year", "cci_sqrt", "smoke",
            "hosp_7", "hosp_30", "hosp_nights_sqrt", "hosp_n_sqrt", 
            "ae_30", "ae_n_sqrt", "abx_30", "home")

full_form <- as.formula(str_c("sep == 'yes' ~ presc + female + ", str_c(covars, collapse = " + ")))
full_fit <- fit_and_summarise(full_form, epi)

# Render with kable
tbl_2 %>%
  rbindlist() %>% 
  .[(tbl_shell[, .(var)]), on = .(var)] %>% 
  merge(full_fit$summary[, .(var, or, p.value)], by = "var", all.x = TRUE, sort = FALSE) %>% 
  render(columns = 2, 
         caption = "Odds of sepsis table", 
         header = c(" " = 1, "Univariate" = 2, "Multivariate" = 2))

# ```

# ```{r table-2-stratified}

# Run a fully adjusted model with gender interaction 
int_form <- as.formula(str_c("sep == 'yes' ~ presc * female + ", str_c(covars, collapse = " + ")))
int_fit <- fit_and_summarise(int_form, epi)
int_fit$summary%>% 
  render(caption = "Multivariate analysis with interaction")

# Run an ajusted model stratified by gender
strat_form <- as.formula(str_c("sep == 'yes' ~ presc + ", str_c(covars, collapse = " + ")))

male_univ <- table_2(epi[female == "no"], tab_sep_odds)
male_univ %>% rbindlist() %>%  render(columns = 1, caption = "Odds of sepsis table (male)", header = c(" " = 1, "Univariate" = 2))

male_fit <- fit_and_summarise(strat_form, epi[female == "no"])
male_fit$summary%>% 
  render(caption = "Multivariate analysis of men")

female_univ <- table_2(epi[female == "yes"], tab_sep_odds)
female_univ %>% rbindlist() %>%  render(columns = 1, caption = "Odds of sepsis table (female)", header = c(" " = 1, "Univariate" = 2))

female_fit <- fit_and_summarise(strat_form, epi[female == "yes"])
female_fit$summary %>% 
  render(caption = "Multivariate analysis of women")

# ```

# ```{r nnh}

# See Bender et al. (2007) for formulas

# This is approximate, but coefficients stay very(!) close
mean_model <- glm(formula = full_form, family = binomial, data = epi) 

as_grid <- with(epi, expand.grid(age = levels(age_cat), female = levels(female)))

n_boot <- bootstrap_nneh
n_smpl <- nrow(epi)


# Helper functions ------------------------------------------------------------------------

model <- function(data, formula = full_form, strip = TRUE){
  # Fit a logistic regression to data. If strip is TRUE, remove unnecessary 
  # objects within the fitted model to avoid memory overflow.
  
  fit <- glm(formula = formula, family = binomial, data = data)
  
  if(strip){
    strip_glm(fit)
  } else {
    fit
  }
}

nneh_part_by_as <- function(df, .f, .m){
  # Calculate exposure impact number or number needed to be exposed
  # for a grid of age and sex levels.
  
  val <- pmap_dbl(as_grid, ~ .f(df[age_cat == ..1 & female == ..2], .m))
  names(val) <- str_c(as_grid$age, as_grid$female)
  val
}

nneh_boot_ci <- function(dt, .f, idx, models, strata = FALSE){
  # Calculate confidence intervals for NNEH or EIN from a bootstrap
  
  if(deparse(substitute(.f)) == "ein"){
    exposed <- "no"
  } else {
    exposed <- "yes"
  }
  
  if(strata){
    boot <- map2(idx, models, ~ nneh_part_by_as(dt[.x][presc == (exposed)], .f, .y))
    nms <- str_c(as_grid$age, as_grid$female)
  } else {
    boot <- map2(idx, models, ~ .f(dt[.x][presc == (exposed)], .y))
    nms <- "all"
  }
  
  boot %>% 
    map(~ ifelse(. <= 0, Inf, .)) %>% # Replace no effect (=negative) with infinite 
    # (an infinite amount of patients could be treated 
    # without any extra sepsis cases)
    transpose() %>% 
    map(~ quantile(., prob = c(0.025, 0.975))) %>% 
    set_names(nms)
}



# Exposure impact number ------------------------------------------------------------------

ard_exp <- function(exposed, model){
  # Calculate the average risk difference (ARD) in the exposed population
  # NOTE: Exposed in this case means "not prescribed"
  #
  # See Bender et al. (2007) for the formula
  
  pr_actual <- predict(model, newdata = exposed, type = "response")
  exposed$presc <- "yes"
  pr_trt <- predict(model, newdata = exposed, type = "response")
  
  mean(pr_actual - pr_trt) # This is the reverse of the formula in the paper (we calculate "harm")
}


ein <- function(exposed, model){
  # Calculate the exposure impact number (EIN), i.e. the effect of 
  # removing exposure from an exposed population. In the context of 
  # this study, this would mean treating previously untreated patients
  # immediately with antibiotics.
  #
  # The EIN is the inverse of the ARD in the exposed population.
  
  1 / ard_exp(exposed, model)
}


# Point estimates
ein_all <- ein(epi[presc == "no"], mean_model)
print(str_c("The exposure impact number was ", ein_all))

ein_strat <- nneh_part_by_as(epi[presc == "no"], ein, mean_model)
print(ein_strat)

# Bootstrapped confidence intervals
if(n_boot > 0){
  set.seed <- 123
  
  ein_idx <- rerun(n_boot, sample(1:n_smpl, n_smpl, replace = TRUE))
  ein_models <- map(ein_idx, ~ model(data = epi[.]))
  
  # Confidence interval for the overall effect
  ein_all_ci <- nneh_boot_ci(epi, ein, ein_idx, ein_models)
  print(ein_all_ci)
  
  # Confidence interval within strata
  ein_strat_ci <- nneh_boot_ci(epi, ein, ein_idx, ein_models, strata = TRUE)
  print(ein_strat_ci)
}



# Number needed to be exposed
ard_un <- function(unexposed, model){
  # Exposed in this case means "not prescribed"
  pr_actual <- predict(model, newdata = unexposed, type = "response")
  unexposed$presc <- "no"
  pr_no <- predict(model, newdata = unexposed, type = "response")
  
  mean(pr_no - pr_actual) # This is the reverse of the formula in the paper (we calculate "harm")
}


nne <- function(unexposed, model){
  # Calculate the number needed to be exposed (NNE), i.e. the effect of 
  # adding exposure to an unexposed population. In the context of 
  # this study, this would mean not treating previously treated patients
  # with antibiotics.
  #
  # The NNE is the inverse of the ARD in the unexposed population.
  
  1 / ard_un(unexposed, model)
}


# Point estimates
nne_all <- nne(epi[presc == "yes"], mean_model)
print(str_c("The number needed to expose was ", nne_all))

nne_strat <- nneh_part_by_as(epi[presc == "yes"], nne, mean_model)
print(nne_strat)

# Bootstrapped confidence intervals
if(n_boot > 0){
  set.seed <- 234
  
  nne_idx <- rerun(n_boot, sample(1:n_smpl, n_smpl, replace = TRUE))
  nne_models <- map(nne_idx, ~ model(data = epi[.]))
  
  # Confidence interval for the overall effect
  nne_all_ci <- nneh_boot_ci(epi, nne, nne_idx, nne_models)
  print(nne_all_ci)
  
  # Confidence interval within strata
  nne_strat_ci <- nneh_boot_ci(epi, nne, nne_idx, nne_models, strata = TRUE)
  print(nne_strat_ci)
}

# ```

# ```{r sens}

# Run some additional analysis to investigate the sensitivity of the results to different definitions of the study population and outcomes

# Run some additional analysis to investigate the association with sepsis in first episode 
first_univ <- table_2(epi[, .SD[1], by = patid], tab_sep_odds)
first_univ %>% rbindlist() %>%  render(columns = 1, caption = "Odds of sepsis table (first)", header = c(" " = 1, "Univariate" = 2))

first_form <- as.formula(str_c("sep == 'yes' ~ presc + female +", str_c(covars, collapse = " + ")))
first <- fit_and_summarise(first_form, epi[, .SD[1], by = patid])
first$summary%>% render()

first_form <- as.formula(str_c("sep == 'yes' ~ presc * female +", str_c(covars, collapse = " + ")))
first_int <- fit_and_summarise(first_form, epi[, .SD[1], by = patid])
first_int$summary%>% render()

first_form <- as.formula(str_c("sep == 'yes' ~ presc + ", str_c(covars, collapse = " + ")))
first_male <- fit_and_summarise(first_form, epi[, .SD[1], by = patid][female == "no"])
first_male$summary%>% render()
first_female <- fit_and_summarise(first_form, epi[, .SD[1], by = patid][female == "yes"])
first_female$summary%>% render()

# Run some additional analysis to investigate the association with death 
tab_died_odds <- partial(tab_odds, outcome = "died == 'yes'")
died_univ <- table_2(epi, tab_died_odds)
died_univ %>% rbindlist() %>%  render(columns = 1, caption = "Odds of death table", header = c(" " = 1, "Univariate" = 2))

died_form <- as.formula(str_c("died == 'yes' ~ presc + female +", str_c(covars, collapse = " + ")))
died <- fit_and_summarise(died_form, epi)
died$summary%>% render()

died_form <- as.formula(str_c("died == 'yes' ~ presc * female +", str_c(covars, collapse = " + ")))
died_int <- fit_and_summarise(died_form, epi)
died_int$summary%>% render()

died_form <- as.formula(str_c("died == 'yes' ~ presc + ", str_c(covars, collapse = " + ")))
died_male <- fit_and_summarise(died_form, epi[female == "no"])
died_male$summary%>% render()
died_female <- fit_and_summarise(died_form, epi[female == "yes"])
died_female$summary%>% render()

# Run some additional analysis to investigate the association with non-UTI/sepsis hospitalisations 
tab_other_odds <- partial(tab_odds, outcome = "other_hosp == 'yes'")
other_univ <- table_2(epi, tab_other_odds)
other_univ %>% rbindlist() %>%  render(columns = 1, caption = "Odds of other hosp table", header = c(" " = 1, "Univariate" = 2))

other_form <- as.formula(str_c("other_hosp == 'yes' ~ presc + female +", str_c(covars, collapse = " + ")))
other <- fit_and_summarise(other_form, epi)
other$summary%>% render()

other_form <- as.formula(str_c("other_hosp == 'yes' ~ presc * female +", str_c(covars, collapse = " + ")))
other_int <- fit_and_summarise(other_form, epi)
other_int$summary%>% render()

other_form <- as.formula(str_c("other_hosp == 'yes' ~ presc + ", str_c(covars, collapse = " + ")))
other_male <- fit_and_summarise(other_form, epi[female == "no"])
other_male$summary%>% render()
other_female <- fit_and_summarise(other_form, epi[female == "yes"])
other_female$summary%>% render()

# ```

# ```{r nne-sens}

# Calculate NNEH and confidence intervals for the secondary/sensitivity analysis
# NOTE: do not run for analysis of sepsis with first episode as there is no effect

died_form <- as.formula(str_c("died == 'yes' ~ presc + female +", str_c(covars, collapse = " + ")))
died_glm <- model(formula = died_form, data = epi) 
nne(epi[presc == "yes"], died_glm) %>% print()

if(n_boot > 0){
  died_boot <- map(nne_idx, ~ model(formula = died_form, data = epi[.]))
  nneh_boot_ci(epi, nne, nne_idx, died_boot) %>% print()
}

other_form <- as.formula(str_c("other_hosp == 'yes' ~ presc + female +", str_c(covars, collapse = " + ")))
other_glm <- model(formula = other_form, data = epi) 
nne(epi[presc == "yes"], other_glm) %>% print()

if(n_boot > 0){
  other_boot <- map(nne_idx, ~ model(formula = other_form, data = epi[.]))
  nneh_boot_ci(epi, nne, nne_idx, other_boot) %>% print()
}

# ```

# ```{r run-everything}
# Helper chunk to run entire document with RStudio
# ```