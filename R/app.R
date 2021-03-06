library(shiny)
library(shinycssloaders)

# Set up the loading gif
options(spinner.color="#0275D8", spinner.color.background="#ffffff", spinner.size=2)

## Load necessary packages, source files, and load data ##
source("setup_model.R")

# Define UI ----
ui <- fluidPage(
  titlePanel("Minnesota COVID-19 Model Sandbox"),
  
  fluidRow(
    column(4,
             wellPanel(
        helpText("Start by inputting values for the Shelter-in-Place End Date and Social Distancing End Date, then click 'Run Simulation'"),
        dateInput("shelter_in_place_end_date", 
                  h4("End Date for Shelter-in-Place (Stay at Home Order)"), 
                  format = "MM d, yyyy",
                  value = ""),
        dateInput("social_distancing_end_date", 
                  h4("End Date for Social Distancing"), 
                  format = "MM d, yyyy",
                  value = ""),
        helpText("Note: The start date of social distancing is fixed at March 23rd, and the start date of shelter-in-place is fixed at March 27th (the days these events occurred in Minnesota)."),
        actionButton("simulationButton", "Run Simulation", icon("play"), style="color: #fff; background-color: #4CAF50"),
        #actionButton("clearSimulationsButton", "Clear Simulations", icon("trash"))
          )
        ),
    column(8,      
      tabsetPanel(
        tabPanel("ICU Bed Demand", withSpinner(plotOutput("icu_bed_demand_plot"), type = 8)), 
        tabPanel("Cumulative Deaths", withSpinner(plotOutput("cumulative_deaths_plot"), type = 8)), 
        tabPanel("Prevalent Infections", withSpinner(plotOutput("prevalent_infections_plot"), type = 8)),
        tabPanel("Cumulative Infections", withSpinner(plotOutput("cumulative_infections_plot"), type = 8)),
        tabPanel("Daily Deaths", withSpinner(plotOutput("daily_deaths_plot"), type = 8)),
        tabPanel("Prevalent Hospitalizations", withSpinner(plotOutput("prevalent_hospitalizations_plot"), type = 8))
      )
      )
    ),
    fluidRow(tableOutput("simulations_table"))
)

# Define server logic ----
server <- function(input, output, session) {
  
  autoInvalidate <- reactiveTimer(10000)
  observe({
    autoInvalidate()
    cat(".")
  })
  
  showModal(modalDialog(
    title = "Information & Disclaimer",
    HTML(paste("👋This tool is designed to make it easy to run simulations using the COVID-19 model developed by the University of Minnesota (documentation: https://mn.gov/covid19/data/modeling/)",
               "✅This model is intended to show the possible differences in outcomes from different mitigation strategies, rather than precisely estimating mortality numbers.  This tool has the same limitations as the underlying model, and <b>you should understand the modeling methodology and its limitations before using this tool</b> ",
               "✅Every model, including this one, relies on a simplified representation of the world. This means many factors that may influence the progression of the disease are not accounted for in this model. ", 
               "✅The code used to create the underlying model was created by the University of Minnesota and the code used to build this web app was created by Carston Hernke. Both sets of code are licensed via the GNU General Public License 3.0, which makes them freely available for reuse. <b>The source code is available at https://github.com/carstonhernke/Model_v3. Contributions are highly encouraged!</b>",  
               sep="<br/>")),
    easyClose = TRUE,
    footer = modalButton("I Understand")
  ))
  
  baseline_date_as_integer = 18343 # set to march 22 2020, per model
  
  session$userData$params = setNames(data.frame(matrix(ncol = 3, nrow = 0)), c("Simulation", 
                                                                               "Shelter-In-Place End Date", 
                                                                               "Social Distancing End Date"))
  session$userData$results = data.frame(matrix(nrow = 0, ncol = 8))
  colnames(session$userData$results) <- c("Simulation", 
                             "Mortality", 
                             "Mortality thru May",
                             "Day ICU Cap Reached",
                             "Max ICU Demand",
                             "Rt Estimate",
                             "Day of Peak Infections",
                             "additional_vulnerable_sd_days")
  session$userData$lst_out_raw <- list()
  session$userData$lst_out <- list()
  
  # clearSimulations <- eventReactive(input$clearSimulationsButton,
  #   ({
  #     session$userData$params = setNames(data.frame(matrix(ncol = 3, nrow = 0)), c("simulation_number", "sip_end_date", "social_distancing_end_date"))
  #     session$userData$results = matrix(nrow = length(1), ncol = 8)
  #     colnames(session$userData$results) <- c("simulation_number",
  #                                             "n_deaths",
  #                                             "n_deaths_may30",
  #                                             "day_icu_cap_reached",
  #                                             "max_icu_demand",
  #                                             "Rt_est",
  #                                             "day_peak_infections",
  #                                             "additional_vulnerable_sd_days")
  #     showNotification("Simulations Cleared")
  # }))

  runModel <- eventReactive(input$simulationButton, {
    scn_vec <- seq(1,input$simulationButton)    # Initializing a matrix to store printed summary output from model
    summary_out <- matrix(nrow = length(scn_vec), ncol = 8)
    colnames(summary_out) <- c("strategy", 
                               "n_deaths", 
                               "n_deaths_may30",
                               "day_icu_cap_reached",
                               "max_icu_demand",
                               "Rt_est",
                               "day_peak_infections",
                               "additional_vulnerable_sd_days")
    
    # Set parameters to their default base case values 
    parms <- parameters(n_icu_beds = )
    
    # Set parameters
    parms$start_time_social_distancing <- 1 # March 23nd
    parms$end_time_social_distancing <- as.integer(isolate(input$social_distancing_end_date) - baseline_date_as_integer)
    parms$start_time_sip <- 6 # March 27th
    parms$end_time_sip <- as.integer(isolate(input$shelter_in_place_end_date) - baseline_date_as_integer)
    
    # Sapecify time horizon of model output (in days); default = 365 (1 year)
    # Day 1 = March 22, 2020
    times <- seq(1, 365, by = parms$timestep)
    
    # Sve parameters to simulations table
    session$userData$params[input$simulationButton,] <- list(as.character(input$simulationButton), 
                                                          isolate(format(as.Date(input$shelter_in_place_end_date),format="%m/%d/%Y")),
                                                          isolate(format(as.Date(input$social_distancing_end_date), format="%m/%d/%Y")))
    
    # Run model
    m_out_raw <- solve_model(parms$init_vec, 
                             times = times,
                             func = covid_19_model_function,
                             parms = parms)
    
    # Store the raw output from each strategy in a list
    session$userData$lst_out_raw <- c(session$userData$lst_out_raw, list(m_out_raw))
    
    # Process output matrix "out" to extract more data
    out <- process_output(m_out_raw,parms)
    session$userData$lst_out <- c(session$userData$lst_out,list(out))
    
    
    ## Store select summary outputs ##
    
    # deaths
    n_deaths <- round(out[nrow(out), "cumulative_deaths"], 0)
    pct_deaths <- round(100 * n_deaths / parms$N, 2)
    n_deaths_may30 <- round(out[70,"cumulative_deaths"],0) # day 70 is may 30
    
    # healthcare demand
    day_icu_cap_reached <- which(out[, "ICU_bed_demand"] >= parms$n_icu_beds)[1]
    max_icu_demand <- round(max(out[, "ICU_bed_demand"]), 0)
    
    # infections
    day_peak_infections <- which.max(out[, "prevalent_infections"])
    
    # Rt estimation (first 20 days)
    lm_Rt <- lm(log(out[1:20,"cumulative_infections"])~out[1:20,"Time"])
    avg_exp_dur <- parms$n_exposed_states/(parms$exposed_transition_rate/parms$timestep)
    avg_inf_dur <- parms$n_infected_states/(parms$infected_transition_rate/parms$timestep)
    Rt_est <- round((1+lm_Rt$coefficients[[2]]*avg_inf_dur)*(1+lm_Rt$coefficients[[2]]*avg_exp_dur),2)
    
    # Scenario features
    # number of additional days distancing for vulnerable (aged 60+)
    n_add_vulnerable_sd_days <- ifelse(parms$sixty_plus_days_past_peak >= 0,
                                       round(max(which(m_out_raw[, "sd60p"] == 1)) - 
                                               max(which(m_out_raw[, "sd"] == 1 | m_out_raw[, "sip"] == 1)),0),
                                       NA)
    
    # Store summary results in matrix
    session$userData$results[input$simulationButton,] <- c(as.character(input$simulationButton),
                                                           n_deaths, 
                                                           n_deaths_may30, 
                                                           day_icu_cap_reached, 
                                                           max_icu_demand,
                                                           Rt_est,
                                                           day_peak_infections,
                                                           n_add_vulnerable_sd_days)
    
    ## Create data.frame for plotting
    df_ls <- lapply(1:length(session$userData$lst_out), FUN = function(x) {
      df <- as.data.frame(session$userData$lst_out[[x]][, 1:6])
      df$t <- 1:nrow(session$userData$lst_out[[x]])
      df$simulation <- paste('#',scn_vec[x],sep='')
      return(df)
    })
    df_out <- do.call(rbind, df_ls)
  }, ignoreInit = TRUE)

  output$icu_bed_demand_plot <- renderPlot({
    ## Function for basic plots of model outputs over time
    plot_func <- function(var_name) {
      var <- sym(var_name)
      plot <- ggplot(runModel(), aes(x = t / 7, y = !! var, color = simulation)) + geom_path() +
        ylab(var_name) + xlab("Time (weeks after March 22nd)") +
        ggtitle(paste0(var_name)) +
        theme(plot.title = element_text(hjust = 0.5))
      return(plot)
    }
    
    ## Generate plots
    plot_func("ICU_bed_demand")
  })
  
  output$cumulative_deaths_plot <- renderPlot({
    ## Function for basic plots of model outputs over time
    plot_func <- function(var_name) {
      var <- sym(var_name)
      plot <- ggplot(runModel(), aes(x = t / 7, y = !! var, color = simulation)) + geom_path() +
        ylab(var_name) + xlab("Time (weeks after March 22nd)") +
        ggtitle(paste0(var_name)) +
        theme(plot.title = element_text(hjust = 0.5))
      return(plot)
    }
    
    ## Generate plots
    plot_func("cumulative_deaths")
  })
  
  output$prevalent_infections_plot <- renderPlot({
     ## Function for basic plots of model outputs over time
    plot_func <- function(var_name) {
      var <- sym(var_name)
      plot <- ggplot(runModel(), aes(x = t / 7, y = !! var, color = simulation)) + geom_path() +
        ylab(var_name) + xlab("Time (weeks after March 22nd)") +
        ggtitle(paste0(var_name)) +
        theme(plot.title = element_text(hjust = 0.5))
      return(plot)
    }
    
    ## Generate plots
    plot_func("prevalent_infections")
  })
  
  output$cumulative_infections_plot <- renderPlot({
    ## Function for basic plots of model outputs over time
    plot_func <- function(var_name) {
      var <- sym(var_name)
      plot <- ggplot(runModel(), aes(x = t / 7, y = !! var, color = simulation)) + geom_path() +
        ylab(var_name) + xlab("Time (weeks after March 22nd)") +
        ggtitle(paste0(var_name)) +
        theme(plot.title = element_text(hjust = 0.5))
      return(plot)
    }
    
    ## Generate plots
    plot_func("cumulative_infections")
  })
  
  
  output$daily_deaths_plot <- renderPlot({
    ## Function for basic plots of model outputs over time
    plot_func <- function(var_name) {
      var <- sym(var_name)
      plot <- ggplot(runModel(), aes(x = t / 7, y = !! var, color = simulation)) + geom_path() +
        ylab(var_name) + xlab("Time (weeks after March 22nd)") +
        ggtitle(paste0(var_name)) +
        theme(plot.title = element_text(hjust = 0.5))
      return(plot)
    }
    
    ## Generate plots
    plot_func("daily_deaths")
  })
  
  
  output$prevalent_hospitalizations_plot <- renderPlot({
    ## Function for basic plots of model outputs over time
    plot_func <- function(var_name) {
      var <- sym(var_name)
      plot <- ggplot(runModel(), aes(x = t / 7, y = !! var, color = simulation)) + geom_path() +
        ylab(var_name) + xlab("Time (weeks after March 22nd)") +
        ggtitle(paste0(var_name)) +
        theme(plot.title = element_text(hjust = 0.5))
      return(plot)
    }
    
    ## Generate plots
    plot_func("prevalent_hospitalizations")
  })
  
  output$simulations_table <- renderTable({
    input$simulationButton
    columns_to_show = c("Simulation",
                        "Shelter-In-Place End Date", 
                        "Social Distancing End Date",
                        "Mortality", 
                        "Mortality thru May",
                        "Day ICU Cap Reached",
                        "Max ICU Demand",
                        "Day of Peak Infections")
    m = merge(x = session$userData$params, y = session$userData$results, by = 'Simulation', all.x = TRUE)
    m[columns_to_show]
  })
}

# Run the app ----
shinyApp(ui = ui, server = server)