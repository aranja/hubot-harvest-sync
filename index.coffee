# Description:
#   Allows Hubot to interact with Harvest's (http://harvestapp.com) time-tracking
#   service.
#
# Dependencies:
#   None
# Configuration:
#   HUBOT_HARVEST_SUBDOMAIN
#
# Commands:
#
#   hubot remember my harvest account <email> with password <password> - Make hubot remember your Harvest credentials
#   hubot forget my harvest account - Make hubot forget your Harvest credentials again
#   hubot start harvest - Restart the last timer.
#   hubot start harvest at <project>/<task>: <notes> - Start a Harvest timer at a given project-task combination
#   hubot stop harvest [at project/task] - Stop the most recent Harvest timer or the one for the given project-task combination.
#   hubot daily harvest [of <user>] [at yyyy-mm-dd] - Show a user's Harvest timers for today (or yours, if noone is specified) or a specific day
#   hubot list harvest tasks [of <user>] - Show the Harvest project-task combinations available to a user (or you, if noone is specified)
#   hubot is harvest down/up - Check if the Harvest API is reachable.
#   hubot remember a harvest migration account <email> with password <password> at <harvest-subdomain> - Make hubot remember external Harvest credentials.
#   hubot remember a harvest migration from <project>[/<task>] to <project>[/<task>] at <harvest-subdomain> - Make hubot remember a timesheet migration setup.
#   hubot forget harvest migrations for <project> at <harvest-subdomain> - Remove timesheet migration from memory
#   hubot migrate [<num> days of ]<harvest-subdomain> harvest - Runs a timesheet migration to an external Harvest
#
# Notes:
#   All commands and command arguments are case-insenitive. If you work
#   on a project "FooBar", hubot will unterstand "foobar" as well. This
#   is also true for abbreviations, so if you don't have similary named
#   projects, "foob" will do as expected.
#
#   Some examples:
#   > hubot remember my harvest account joe@example.org with password doe
#   > hubot list harvest tasks
#   > hubot start harvest at myproject/important-task: Some notes go here.
#   > hubot start harvest at myp/imp: Some notes go here.
#   > hubot daily harvest of nickofotheruser
#
#   Full command descriptions:
#
#   hubot remember my harvest account <email> with password <password>
#     Saves your Harvest credentials to allow Hubot to track
#     time for you.
#
#   hubot forget my harvest account
#     Deletes your account credentials from Hubt's memory.
#
#  hubot start harvest
#    Examines the list of timers for today and creates a new timer with
#    the same properties as the most recent one.
#
#   hubot start harvest at <project>/<task>: <notes>
#     Starts a timer for a task at a project (both of which may
#     be abbreviated, Hubot will ask you if your input is
#     ambigious). An existing timer (if any) will be stopped.
#
#   hubot stop harvest [at <project>/<task>]
#     Stops the timer for a task, if any. If no project is given,
#     stops the first active timer it can find. The project and
#     task arguments may be abbreviated as with start.
#
#   hubot daily harvest [of <user>] [on yyyy-mm-dd]
#     Hubot responds with your/a specific user's entries
#     for the given date; if no date is given, assumes today.
#     If user is ommitted, you are assumed; if both the user and
#     the date are ommited, your entries for today will be displayed.
#
#   hubot list harvest tasks [of <user>]
#     Gives you a list of all project/task combinations available
#     to you or a specific user. You can use these for the start command.
#
#   hubot remember a harvest migration account <email> with password <password> at <harvest-subdomain>
#     Saves Harvest credentials for an external Harvest account to
#     allow Hubot to perform timesheet migrations.
#
#   hubot remember a harvest migration from <project>[/<task>] to <project>[/<task>] at <harvest-subdomain>
#     Saves a Harvest migration of timesheets from one project in your
#     Harvest account to a project on another Harvest account.
#     Project and task arguments may be abbreviated.
#     Defaults to migrating all tasks to a "dev" task.
#
#   hubot forget harvest migrations for <project> at <harvest-subdomain> - Remove timesheet migration from memory
#     Remove timesheet migration for a specific project from memory
#     so it won't be migrated. If you need to change a configuration,
#     just remove it and create it anew.
#
#   hubot list harvest migrations for <harvest-subdomain>
#     Hubot responds with the currently remembered migrations for an
#     external Harvest account.
#
#   hubot migrate [<num> days of ]<harvest-subdomain> harvest
#     Starts a Harvest timesheet migration. Comparing the past few
#     days (7 by default) and updates the external Harvest as needed.
#
#   Note on HUBOT_HARVEST_SUBDOMAIN:
#     This is the subdomain you access the Harvest service with, e.g.
#     if you have the Harvest URL http://yourcompany.harvestapp.com
#     you should set this to "yourcompany" (without the quotes).
#
# Author:
#   Quintus @ Asquera
#
http = require("http")
async = require("async")

unless process.env.HUBOT_HARVEST_SUBDOMAIN
  console.log "Please set HUBOT_HARVEST_SUBDOMAIN in the environment to use the harvest plugin script."

# Checks if we have the information necessary for making requests
# for a user. If we don't, reply accordingly and return null. Otherwise,
# return the user object.
# If `test_user` is supplied, checks the credentials for the user
# with that name, otherwise the sender of `msg` is checked.
check_user = (robot, msg, test_user = null) ->
  # Detect the user; if none is passed, assume the sender.
  user = null
  if test_user
    user = robot.brain.userForName(test_user)
    unless user
      msg.reply "#{msg.match[2]}? Whoʼs that?"
      return null
  else
    user = msg.message.user

  # Check if we know the detected user's credentials.
  unless user.harvest_account
    if user == msg.message.user
      msg.reply "You have to tell me your Harvest credentials first."
    else
      msg.reply "I didnʼt crack #{user.name}ʼs Harvest credentials yet, but Iʼm working on it… Sorry for the inconvenience."
    return null

  return user

# Checks if we have authentication information for a third party Harvest
# account. If we don't, reply accordingly and return null. Otherwise,
# return the HarvestAccount.
check_external_account = (robot, msg, subdomain) ->
  account = robot.brain.get "harvest-#{subdomain}"
  unless account
    msg.reply "You have to give migration credentials for #{subdomain} first."
    return null
  return account

# Checks if there are migrations registered for a third party Harvest
# account. Returns null or the migrations accordingly.
check_migrations = (robot, msg, subdomain) ->
  migrations = robot.brain.get "harvest-#{subdomain}-migrations"
  unless migrations && migrations.length
    msg.reply "Sorry, there are no migrations set up for #{subdomain}."
    return null
  return migrations

check_error = (err, res) ->
  if err
    return err
  else if res and !(200 <= res.statusCode <= 299)
    return new Error("Status code #{res.statusCode}")
  return null

handle_error = (msg, err, action) ->
  if err
    msg.reply "Failed to #{action}: #{err.message}"
    return true
  return false

date_plus_days = (days) ->
  date = new Date()
  date.setDate(date.getDate() + days)
  date

# Parses an email argument, fixing up issues with the hubot-slack adapter.
parse_email = (email) ->
  email.replace(/\s*mailto:.+/i, '')

# Issues an empty GET request to harvest to test whether the service is
# available at the moment. The callback gets passed an exception object
# describing the connection error; if everything is fine it gets passed
# null.
check_harvest_down = (callback) ->
  opts =
    headers:
      "Content-Type": "application/json"
      "Accept": "application/json"
    method: "GET"
    host: "#{process.env.HUBOT_HARVEST_SUBDOMAIN}.harvestapp.com"
    port: 80
    path: "/account/who_am_i"
  req = http.request opts, (response) ->
    callback null
  req.on "error", (error) ->
    callback error
  req.setTimeout 5000
  req.end()

### Definitions for hubot ###
module.exports = (robot) ->

  # Check if Harvest is available.
  robot.respond /is harvest (down|up)/i, (msg) ->
    check_harvest_down (error) ->
      if error
        msg.reply("Harvest is down; exact error: #{error}")
      else
        msg.reply("Harvest is up.")

  # Provide facility for saving the account credentials.
  robot.respond /remember my harvest account (.+) with password (.+)/i, (msg) ->
    account = new HarvestAccount parse_email(msg.match[1]), msg.match[2]
    harvest = new HarvestService(account)

    # If the credentials are valid, remember them, otherwise
    # tell the user they are wrong.
    harvest.test msg, (valid) ->
      if valid
        msg.message.user.harvest_account = account
        msg.reply "Thanks, Iʼll remember your credentials. Have fun with Harvest."
      else
        msg.reply "Uh-oh – I just tested your credentials, but they appear to be wrong. Please specify the correct ones."

  # Allows a user to delete his credentials.
  robot.respond /forget my harvest account/i, (msg) ->
    msg.message.user.harvest_account = null
    msg.reply "Okay, I erased your credentials from my memory."

  # Retrieve your or a specific user's timesheet for today.
  robot.respond /daily harvest( of (\w+))?( on (\d{4})-(\d{2})-(\d{2}))?/i, (msg) ->
    unless user = check_user(robot, msg, msg.match[2])
      return
    harvest = new HarvestService(user.harvest_account)

    if msg.match[3]
      target_date = new Date(parseInt(msg.match[4]), parseInt(msg.match[5] - 1), parseInt(msg.match[6])) # Month starts at 0

    if target_date
      harvest.daily_at msg, target_date, (err, body) ->
        if handle_error msg, err, "retrieve entry information"
          return
        if body.day_entries.length == 0
          msg.reply "#{user.name} has no entries on #{target_date}."
        else
          msg.reply "#{user.name}'s entries on #{target_date}:"

        for entry in body.day_entries
          if entry.ended_at == ""
            msg.reply "• #{entry.project} (#{entry.client}) → #{entry.task} <#{entry.notes}> [running since #{entry.started_at} (#{entry.hours}h)]"
          else
            msg.reply "• #{entry.project} (#{entry.client}) → #{entry.task} <#{entry.notes}> [#{entry.started_at} – #{entry.ended_at} (#{entry.hours}h)]"
    else
      harvest.daily msg, (err, body) ->
        if handle_error msg, err, "retrieve entry information"
          return
        msg.reply "Your entries for today, #{user.name}:"
        for entry in body.day_entries
          if entry.ended_at == ""
            msg.reply "• #{entry.project} (#{entry.client}) → #{entry.task} <#{entry.notes}> [running since #{entry.started_at} (#{entry.hours}h)]"
          else
            msg.reply "• #{entry.project} (#{entry.client}) → #{entry.task} <#{entry.notes}> [#{entry.started_at} – #{entry.ended_at} (#{entry.hours}h)]"

  # List all project/task combinations that are available to a user.
  robot.respond /list harvest tasks( of (.+))?/i, (msg) ->
    unless user = check_user(robot, msg, msg.match[2])
      return

    harvest = new HarvestService(user.harvest_account)

    harvest.daily msg, (err, body) ->
      if handle_error msg, err, "retrieve project/task list"
        return
      msg.reply "The following project/task combinations are available for you, #{user.name}:"
      for project in body.projects
        msg.reply "• Project #{project.name}"
        for task in project.tasks
          msg.reply "  ‣ #{task.name} (#{if task.billable then 'billable' else 'non-billable'})"

  # Kick off a new timer, stopping the previously running one, if any.
  robot.respond /start harvest at (.+)\/(.+): (.*)/i, (msg) ->
    unless user = check_user(robot, msg)
      return

    harvest = new HarvestService(user.harvest_account)
    project = msg.match[1]
    task    = msg.match[2]
    notes   = msg.match[3]

    harvest.start msg, project, task, notes, (err, body) ->
      if handle_error msg, err, "start timer"
        return
      if body.hours_for_previously_running_timer?
        msg.reply "Previously running timer stopped at #{body.hours_for_previously_running_timer}h."
      msg.reply "OK, I started tracking you on #{body.project}/#{body.task}."

  robot.respond /start harvest$/i, (msg) ->
    unless user = check_user(robot, msg)
      return

    harvest = new HarvestService(user.harvest_account)

    harvest.restart msg, (err, body) ->
      if handle_error msg, err, "start timer"
        return
      if body.hours_for_previously_running_timer?
        msg.reply "Previously running timer stopped at #{body.hours_for_previously_running_timer}h."
      msg.reply "OK, I started tracking you on #{body.project}/#{body.task}."

  # Stops the timer running for a project/task combination,
  # if any. If no combination is given, stops the first
  # active timer available.
  robot.respond /stop harvest( at (.+)\/(.+))?/i, (msg) ->
    unless user = check_user(robot, msg)
      return

    harvest = new HarvestService(user.harvest_account)
    if msg.match[1]
      project = msg.match[2]
      task    = msg.match[3]

      harvest.stop msg, project, task, (err, body) ->
        if handle_error msg, err, "stop timer"
          return
        msg.reply "Timer stopped (#{body.hours}h)."
    else
      harvest.stop_first msg, (err, body) ->
        if handle_error msg, err, "stop timer"
          return
        msg.reply "Timer stopped (#{body.hours}h)."

  # Sets up a migration account at a third party harvest app.
  # This is used to sync timesheets using the following commands.
  robot.respond /remember a harvest migration account (.+) with password (.+) at (.+)/i, (msg) ->
    account = new HarvestAccount parse_email(msg.match[1]), msg.match[2], msg.match[3]
    harvest = new HarvestService(account)

    # If the credentials are valid, remember them, otherwise
    # tell the user they are wrong.
    harvest.test msg, (valid) ->
      if valid
        robot.brain.set "harvest-#{msg.match[3]}", account
        msg.reply "Thanks, Iʼll remember the migration credentials."
      else
        msg.reply "Uh-oh – I just tested the credentials, but they appear to be wrong. Please specify the correct ones."

  # Sets up a migration rule from own harvest to a third party.
  robot.respond /remember a harvest migration from (.+)(?:\/(.+))? to (.+)(?:\/(.+))? at (.+)/i, (msg) ->
    [_, source_project, source_task, target_project, target_task, subdomain] = msg.match
    source_task or= "*"
    target_task or= "dev"
    subdomain = subdomain.toLowerCase()

    unless user = check_user(robot, msg)
      return
    unless to_account = check_external_account(robot, msg, subdomain)
      return

    from_harvest = new HarvestService(user.harvest_account)
    to_harvest = new HarvestService(to_account)

    from_harvest.find_project_and_task msg, source_project, source_task, (err, source_project, source_task) ->
      if handle_error msg, err, "finding source project"
        return
      to_harvest.find_project_and_task msg, target_project, target_task, (err, target_project, target_task) ->
        if handle_error msg, err, "finding target project"
          return
        migrations = robot.brain.get("harvest-#{subdomain}-migrations") || []
        migration = migrations.filter((m) -> m.source_project.id == source_project.id)[0]

        migration = new HarvestMigration(migration || {source_project, target_project})

        if migration.target_project.id != target_project.id
          return msg.reply "Existing migration configured for #{migration.target_project.name} instead of #{target_project.name}"

        migration.add_task_rule(source_task, target_task)

        migrations = migrations.filter((m) -> m.source_project.id != migration.source_project.id).concat [migration]
        robot.brain.set("harvest-#{subdomain}-migrations", migrations)

        unless source_task
          msg.reply "Thanks, I'll remember to migrate #{source_project.name} by default to #{target_project.name}/#{target_task.name} at #{subdomain}"
        else
          msg.reply "Thanks, I'll remember to migrate from #{source_project.name}/#{source_task.name} to #{target_project.name}/#{target_task.name} at #{subdomain}"

  robot.respond /forget (?:a|all)? harvest migrations? for (.+) (?:to|at) (.+)/i, (msg) ->
    [_, source_project, subdomain] = msg.match
    subdomain = subdomain.toLowerCase()

    unless user = check_user(robot, msg)
      return
    unless to_account = check_external_account(robot, msg, subdomain)
      return

    from_harvest = new HarvestService(user.harvest_account)
    to_harvest = new HarvestService(to_account)

    from_harvest.find_project_and_task msg, source_project, "*", (err, source_project, source_task) ->
      if handle_error msg, err, "finding project"
        return
      migrations = robot.brain.get("harvest-#{subdomain}-migrations") || []
      new_migrations = migrations.filter((m) -> m.source_project.id != source_project.id)

      if migrations.length == new_migrations.length
        return msg.reply "Project " + source_project + " is not configured for timesheet migration."

      robot.brain.set("harvest-#{subdomain}-migrations", new_migrations)
      msg.reply "Thanks, I'll remember to not migration #{source_project.name} to #{subdomain}"

  robot.respond /list harvest migrations (?:for|to) (.+)/i, (msg) ->
    subdomain = msg.match[1]
    migrations = robot.brain.get("harvest-#{subdomain}-migrations") || []

    if migrations.length == 0
      msg.reply "No migrations found for #{subdomain}"
    for migration in migrations
      msg.reply "Migrating #{migration.source_project.name} to #{migration.target_project.name}"

  robot.respond /migrate (?:(\d+) days of )?(.+) harvest/i, (msg) ->
    [_, days, subdomain] = msg.match
    days ?= 7

    unless user = check_user(robot, msg)
      return
    unless to_account = check_external_account(robot, msg, subdomain)
      return
    unless migrations = check_migrations(robot, msg, subdomain)
      return

    from_harvest = new HarvestService(user.harvest_account)
    to_harvest = new HarvestService(to_account)

    async.mapSeries migrations, (migration, callback) ->
      migration = new HarvestMigration(migration)
      migration.run msg, from_harvest, to_harvest, days, (err, migrated_hours) ->
        if err
          msg.reply "Encountered error migrating #{migration.source_project.name}: #{err}"
        if migrated_hours > 0
          msg.reply "Migrated #{migrated_hours.toFixed(2)} #{migration.source_project.name} hours to #{to_harvest.account.subdomain}."
        else if migrated_hours < 0
          msg.reply "Deleted #{(-migrated_hours).toFixed(2)} #{migration.source_project.name} hours from #{to_harvest.account.subdomain}."
        else if !err
          msg.reply "#{migration.source_project.name} is already in sync with #{to_harvest.account.subdomain}."
        callback()

# Class encapsulating a user's Harvest credentials; safe to store
# in Hubot's Redis brain (no methods, this is a data-only construct).
class HarvestAccount

  # Create a new harvest account. Pass in the account's email and the
  # password used to access harvest. These credentials are the same you
  # use for logging into Harvest's web service.
  constructor: (email, password, subdomain) ->
    @email     = email
    @password  = password
    @subdomain = subdomain if subdomain

# Class encapsulating a harvest migration rule; safe to store in
# Hubot's Redis brain (no methods, this is a data-only construct).
class HarvestMigration

  # Create a new harvet migration. Pass in the name of project and task
  # to migrate from and to.
  constructor: ({source_project, target_project, task_default_id, task_mapping}) ->
    @source_project = {name: source_project.name, id: source_project.id}
    @target_project = {name: target_project.name, id: target_project.id}
    @task_default_id = task_default_id || null
    @task_mapping = task_mapping || []

  add_task_rule: (from_task, to_task) ->
    if !from_task
      @task_default_id = to_task.id
    else
      @task_mapping[from_task.id] = to_task.id

  run: (msg, source_harvest, target_harvest, days = 7, callback) ->
    date_range = (date_plus_days(-i) for i in [0...days])
    to_date = date_range[0]
    from_date = date_range[date_range.length - 1]
    migrated_hours = 0

    # Wrap callback so migrated_hours is always returned.
    callback = do (callback) ->
      (err) -> callback(err, migrated_hours)

    # Get reports from source and target harvest.
    source_harvest.report msg, @source_project.id, from_date, to_date, (err, source_entries) =>
      if err then return callback new Error("While fetching source report: #{err.message}")

      # Get entries for each day in target harvest. We use the daily api since
      # we probably don't have admin access to the target harvest.
      async.mapLimit date_range, 3, (date, cb) ->
        target_harvest.daily_at msg, date, (err, body) ->
          cb err, body && body.day_entries
      , (err, target_entries) =>
        if err then callback new Error("While fetching target report: #{err.message}")

        # Calculate number of hours per day and target task in source.
        source_entries = source_entries.reduce (days, entry) =>
          if target_task = @target_task_for(entry.task_id)
            key = "#{entry.spent_at},#{target_task}"
            days[key] ||= 0
            days[key] += entry.hours
          days
        , {}

        # Flatten target entries
        target_entries = target_entries.reduce ((all, entries) -> all.concat(entries)), []

        # Find a synced entry in target by day and task to update or delete.
        redundant_counter = 0
        target_entries = target_entries.reduce (days, entry) =>
          unless entry.notes?.indexOf("#sync") >= 0 and parseInt(entry.project_id, 10) == @target_project.id
            return days
          key = "#{entry.spent_at},#{entry.task_id}"
          unless key of days
            days[key] = entry
          else
            days["redundant_#{redundant_counter++}"] = entry
          days
        , {}

        jobs = [];
        for own key, hours of source_entries
          hours = Math.round(hours * 100) / 100
          [spent_at, task_id] = key.split ','

          entry = target_entries[key] || {task_id, spent_at, project_id: @target_project.id, notes: "#sync", hours: 0}
          delete target_entries[key]

          if entry.hours == hours
            continue

          diff = hours - entry.hours
          entry.hours = hours
          if entry.id
            jobs.push ["update_entry", entry, diff]
          else
            jobs.push ["create_entry", entry, diff]

        for own key, entry of target_entries
          jobs.push ["delete_entry", entry, -entry.hours]

        async.mapLimit jobs, 3, (job, callback) ->
          [func, entry, diff] = job
          target_harvest[func] msg, entry, (err) ->
            migrated_hours += diff unless err
            callback null, err
        , (err, errs) ->
          errs = errs.filter((err) -> err)
          if errs.length == 1
            err = errs[0]
          else if errs.length > 0
            err = new Error("First of #{errs.length} errors: #{errs[0].message}")
          callback(err)

  target_task_for: (source_task_id) ->
    if source_task_id of @task_mapping
      @task_mapping[source_task_id]
    else
      @task_default_id

# This class represents a user's connection to the Harvest API;
# it is bound to a specific account and cannot be stored permanently
# in Hubot's (Redis) brain.
#
# The API calls are asynchronous, i.e. the methods executing
# the request immediately return. To process the response,
# you have to attach a callback to the method call, which
# unless documtened otherwise will receive two arguments,
# the first being the response's status code, the second
# one is the response's body as a JavaScript object created
# via `JSON.parse`.
class HarvestService

  # Creates a new connection to the Harvest API for the given
  # account.
  constructor: (account) ->
    subdomain = account.subdomain || process.env.HUBOT_HARVEST_SUBDOMAIN
    @base_url = "https://#{subdomain}.harvestapp.com"
    @account = account

  # Tests whether the account credentials are valid.
  # If so, the callback gets passed `true`, otherwise
  # it gets passed `false`.
  test: (msg, callback) ->
    this.request(msg).path("account/who_am_i").get() (err, res, body) ->
      if err = check_error(err, res)
        callback false
      else
        callback true

  # Issues /daily to the Harvest API.
  daily: (msg, callback) ->
    this.request(msg).path("/daily").get() (err, res, body) ->
      if err = check_error(err, res)
        callback err
      else
        callback null, JSON.parse(body)

  # Issues /daily/<dayofyear>/<year> to the Harvest API.
  daily_at: (msg, date, callback) ->
    this.request(msg).path("/daily/#{this.day_of_year(date)}/#{date.getFullYear()}").get() (err, res, body) ->
      if err = check_error(err, res)
        callback err
      else
        callback null, JSON.parse(body)

  # Issues /projects/<project_id>/entries?from=<from>&to=<to> to the harvest API.
  report: (msg, project_id, from_date, to_date, callback) ->
    path = "/projects/#{project_id}/entries?from=#{this.date_arg(from_date)}&to=#{this.date_arg(to_date)}"
    this.request(msg).path(path).get() (err, res, body) ->
      if err = check_error(err, res)
        callback err
      else
        callback null, JSON.parse(body).map (record) -> record.day_entry

  create_entry: (msg, entry, callback) ->
    path = "/daily/add"
    data = JSON.stringify(entry)
    this.request(msg).path(path).post(data) (err, res, body) ->
      if err = check_error(err, res)
        callback err
      else
        callback null, JSON.parse(body)

  update_entry: (msg, entry, callback) ->
    path = "/daily/update/#{entry.id}"
    data = JSON.stringify(entry)
    this.request(msg).path(path).post(data) (err, res, body) ->
      if err = check_error(err, res)
        callback err
      else
        callback null, JSON.parse(body)

  delete_entry: (msg, entry, callback) ->
    path = "/daily/delete/#{entry.id}"
    this.request(msg).path(path).del() (err, res, body) ->
      if err = check_error(err, res)
        callback err
      else
        callback()

  restart: (msg, callback) ->
    this.daily msg, (err, body) =>
      if err then return callback err

      if body.day_entries.length == 0
        msg.reply "No last entry to restart, sorry."
      else
        last_entry = body.day_entries.pop()
        data =
          notes: last_entry.notes
          project_id: last_entry.project_id
          task_id: last_entry.task_id
        this.request(msg).path("/daily/add").post(JSON.stringify(data)) (err, res, body) ->
          if err = check_error(err, res)
            callback err
          else
            callback null, JSON.parse(body)

  # Issues /daily/add to the Harvest API to add a new timer
  # starting from now.
  start: (msg, target_project, target_task, notes, callback) ->
    this.find_project_and_task msg, target_project, target_task, (project, task) =>
      # OK, task and project found. Start the tracker.
      data =
        notes: notes
        project_id: project.id
        task_id: task.id
      this.request(msg).path("/daily/add").post(JSON.stringify(data)) (err, res, body) ->
        if err = check_error(err, res)
          callback err
        else
          callback null, JSON.parse(body)

  # Issues /daily/timer/<id> to the Harvest API to stop
  # the timer running at `entry.id`. If that timer isn't
  # running, replys accordingly, otherwise calls the callback
  # when the operation has finished.
  stop_entry: (msg, entry, callback) ->
    if entry.timer_started_at?
      this.request(msg).path("/daily/timer/#{entry.id}").get() (err, res, body) ->
        if err = check_error(err, res)
          callback err
        else
          callback null, JSON.parse(body)
    else
      msg.reply "This timer is not running."

  # Issues /daily/timer/<id> to the Harvest API to stop
  # the timer running at <id>, which is determined by
  # looking up the current day_entry for the given
  # project/task combination. If no entry is found (i.e.
  # no timer has been started for this combination today),
  # replies with an error message and doesn't executes the
  # callback.
  stop: (msg, target_project, target_task, callback) ->
    this.find_day_entry msg, target_project, target_task, (err, entry) =>
      if err then return callback err
      this.stop_entry msg, entry, callback

  # Issues /daily/timer/<id> to the Harvest API to stop
  # the timer running at <id>, which is the first active
  # timer it can find in today's timesheet, then calls the
  # callback. If no active timer is found, replies accordingly
  # and doesn't execute the callback.
  stop_first: (msg, callback) ->
    this.daily msg, (err, body) =>
      if err then return callback err
      found_entry = null
      for entry in body.day_entries
        if entry.timer_started_at?
          found_entry = entry
          break

      if found_entry?
        this.stop_entry msg, found_entry, callback
      else
        msg.reply "Currently there is no timer running."

  # (internal method)
  # Assembles the basic parts of a request to the Harvest
  # API, i.e. the Content-Type/Accept and authorization
  # headers. The returned HTTPClient object can (and should)
  # be customized further by calling path() and other methods
  # on it.
  request: (msg) ->
    req = msg.http(@base_url).headers
      "Content-Type": "application/json"
      "Accept": "application/json"
    .auth(@account.email, @account.password)
    return req

  # (internal method)
  # Searches through all projects available to the sender of
  # `msg` for a project whose name inclues `target_project`.
  # If exactly one is found, query all tasks available for the
  # sender in this projects, and if exactly one is found,
  # execute the callback with the project object as the first
  # and the task object as the second argument. If more or
  # less than one project or task are found to match the query,
  # reply accordingly to the user (the callback never gets
  # executed in this case).
  find_project_and_task: (msg, target_project, target_task, callback) ->
    this.daily msg, (err, body) ->
      if err then callback err

      # Search through all possible projects for the matching ones
      projects = []
      for project in body.projects
        if project.name.toLowerCase().indexOf(target_project.toLowerCase()) != -1
          if project.name == target_project
            projects = [project] # Exact match
            break
          else
            projects.push(project)

      # Ask the user if the project name is ambivalent
      if projects.length == 0
        msg.reply "Sorry, no matching projects found."
        return
      else if projects.length > 1
        msg.reply "I found the following #{projects.length} projects for your query, please be more precise:"
        for project in projects
          msg.reply "• #{project.name}"
        return

      # Exit early if only project is being searched for
      if target_task == "*"
        return callback null, projects[0]

      # Repeat the same process for the tasks
      tasks = []
      for task in projects[0].tasks
        if task.name.toLowerCase().indexOf(target_task.toLowerCase()) != -1
          if task.name == target_task
            tasks = [task] # Exact match
            break
          else
            tasks.push(task)

      # Ask the user if the task name is ambivalent
      if tasks.length == 0
        msg.reply "Sorry, no matching tasks found."
      else if tasks.length > 1
        msg.reply "I found the following #{tasks.length} tasks for your query, please be more pricese:"
        for task in tasks
          msg.reply "• #{task.name}"
        return

      # Execute the callback with the results
      callback null, projects[0], tasks[0]

  # (internal method)
  # Searches through all entries made for today and tries
  # to find a running timer for the given project/task
  # combination.
  # If it is found, the respective entry object is passed to
  # the callback, otherwise an error message is replied and
  # the callback doesn't get executed.
  find_day_entry: (msg, target_project, target_task, callback) ->
    this.find_project_and_task msg, target_project, target_task, (err, project, task) =>
      if err then return callback err
      this.daily msg, (err, body) ->
        if err then return callback err
        # For some unknown reason, the daily entry IDs are strings
        # instead of numbers, causing the comparison below to fail.
        # So, convert our target stuff to strings as well.
        project_id = "#{project.id}"
        task_id    = "#{task.id}"
        # Iterate through all available entries for today
        # and try to find the requested ID.
        found_entry = null
        for entry in body.day_entries
          if entry.project_id == project_id and entry.task_id == task_id and entry.timer_started_at?
            found_entry = entry
            break

        # None found
        unless found_entry?
          msg.reply "I couldnʼt find a running timer in todayʼs timesheet for the combination #{target_project}/#{target_task}."
          return

        # Execute the callback with the result
        callback null, found_entry

  # Takes a Date object and figures out which day in its
  # year it represents and returns that one. Leap years
  # are honoured.
  day_of_year: (date) ->
    start = new Date(date.getFullYear(), 0, 1)
    return Math.ceil((date - start) / 86400000)

  # Takes a Date object and formats it as a date argument
  # which Harvest expects.
  date_arg: (date) ->
    month = (101 + date.getMonth() + "")[1..2]
    day = (100 + date.getDate() + "")[1..2]
    return "#{date.getFullYear()}#{month}#{day}"
