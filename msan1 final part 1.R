# =============================================================================
# Creating a Strategus Analysis Specification: msan1 Part 1
# =============================================================================
#
# Study question:
#   Among patients with testicular germ cell cancer treated with etoposide,
#   what is the relative risk of an acute allergic reaction to etoposide in 
#   those who have received at least one Covid‑19 vaccination prior to etoposide 
#   initiation compared with those who have not received any Covid‑19 vaccination?

#install and load
install.packages(c("DatabaseConnector", "SqlRender", "dplyr"))
install.packages("remotes")
install.packages("Eunomia")
remotes::install_github("OHDSI/ROhdsiWebApi")
remotes::install_github("OHDSI/CohortGenerator")
remotes::install_github("OHDSI/CohortDiagnostics")
remotes::install_github("OHDSI/Strategus")
remotes::install_github("OHDSI/CohortIncidence")
remotes::install_github("OHDSI/Characterization")
library(DatabaseConnector)
library(CohortGenerator)
library(CohortDiagnostics)
library(SqlRender)
library(dplyr)
library(ROhdsiWebApi)
library(Strategus)
library(CohortIncidence)
library(Characterization)


dir.create("inst/settings", recursive = TRUE, showWarnings = FALSE)

#connect to ATLAS and test connection
baseUrl <- "https://atlas-demo.ohdsi.org/WebAPI"
# List available data sources on this WebAPI
ROhdsiWebApi::getWebApiVersion(baseUrl = baseUrl)

#Generate cohorts
cohortDefinitionSet <- ROhdsiWebApi::exportCohortDefinitionSet(
  baseUrl       = baseUrl,
  cohortIds     = c(
    1796434, # Germ Cell Tumor treated with Etoposide + Covid Vaccine exposure
    1796435,  # Germ cell tumor treated with Etoposide + NO Covid vaccine exposure
    1796456 # Etoposide allergy (Outcome cohort)
  ),
  generateStats = TRUE
)

cohortDefinitionSet[, c("cohortId", "cohortName")]

# CohortDiagnostics

cgModule <- CohortGeneratorModule$new()

cohortDefinitionSharedResource <- cgModule$createCohortSharedResourceSpecifications(
  cohortDefinitionSet = cohortDefinitionSet
)

cohortGeneratorModuleSpecifications <- cgModule$createModuleSpecifications(
  generateStats = TRUE                    # default: TRUE
)
# model specifications

cdModule <- CohortDiagnosticsModule$new()

cohortDiagnosticsModuleSpecifications <- cdModule$createModuleSpecifications(
  cohortIds = NULL,                           # default: NULL (all cohorts)
  runInclusionStatistics = TRUE,              # default: TRUE
  runIncludedSourceConcepts = TRUE,           # default: TRUE
  runOrphanConcepts = TRUE,                   # default: TRUE
  runTimeSeries = FALSE,                      # default: FALSE
  runVisitContext = TRUE,                     # default: TRUE
  runBreakdownIndexEvents = TRUE,             # default: TRUE
  runIncidenceRate = TRUE,                    # default: TRUE
  runCohortRelationship = TRUE,               # default: TRUE
  runTemporalCohortCharacterization = TRUE,   # default: TRUE
  minCharacterizationMean = 0.01,             # default: 0.01
  irWashoutPeriod = 0                         # default: 0
  # temporalCovariateSettings = <module default covariate settings>
)

# CohortIncidence

ciModule <- CohortIncidenceModule$new()

targets <- list(
  CohortIncidence::createCohortRef(id = 1, name = "Covid vaccine"),
  CohortIncidence::createCohortRef(id = 2, name = "No Covid vaccine")
)

outcomes <- list(
  CohortIncidence::createOutcomeDef(
    id = 1,
    name = "Etoposide allergy",
    cohortId = 3,          # default: 0 (must override)
    cleanWindow = 9999     # default: 0 (we set 9999 = one event per person)
  )
)

tars <- list(
  CohortIncidence::createTimeAtRiskDef(
    id = 1,
    startWith = "start",   # default: "start"
    endWith = "end"        # default: "end"
  ),
  CohortIncidence::createTimeAtRiskDef(
    id = 2,
    startWith = "start",   # default: "start"
    endWith = "start",     # override: anchor end to start
    endOffset = 365        # default: 0 (we set 365 for fixed 1-year window)
  )
)

incidenceAnalysis <- CohortIncidence::createIncidenceAnalysis(
  targets = c(1, 2),
  outcomes = c(3),
  tars = c(1, 2)
)

irDesign <- CohortIncidence::createIncidenceDesign(
  targetDefs = targets,
  outcomeDefs = outcomes,
  tars = tars,
  analysisList = list(incidenceAnalysis),
  strataSettings = CohortIncidence::createStrataSettings(
    byYear = TRUE,         # default: FALSE
    byGender = TRUE        # default: FALSE
  )
)

cohortIncidenceModuleSpecifications <- ciModule$createModuleSpecifications(
  irDesign = irDesign$toList()
)
