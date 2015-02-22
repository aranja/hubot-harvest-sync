hubot-harvest
=============

A fork of the [community harvest script](https://github.com/github/hubot-scripts/blob/master/src/scripts/harvest.coffee)
with additional support for one-way synchronisation of timesheets to an external Harvest account. This scratches our itch quite well when working for a client through a middleman. Most of agencies use Harvest, like us, for time tracking and invoicing.

The problem this plugin solves is quite precise and the implementation is as well so it may not be useful to you. Here are the details:

* Only supports one-way synchronisation from your Harvest account to another Harvest account.
* Supports syncing to multiple external Harvest accounts.
* Supports syncing project to project (1-to-1 for now), task to task, or all tasks to one task.
* Uses the saved credentials of your chat user to query timesheets to sync. Needs to be admin.
* Uses global saved credentials for external accounts, to query and save changes on the other side.
* One Harvest user for each external Harvest domain. Does not need to have admin access there.

## Setup

In your hubot-config, install this script with `npm i hubot-harvest-sync --save`.
Add it to a `external-scripts.json` file in the root of your config like this:

```
["hubot-harvest-sync"]
```

Then restart or redeploy your hubot. 

## Use

Then just chat with your hubot:

```
# Configure source account. Admin. Associated with your chat user. 
hubot remember my harvest account <email> with password <password>

# Register one or more target accounts by Harvest subdomain.
hubot remember a harvest migration account <email> with password <password> at <harvest-subdomain>

# Configure one or more project/task mappings. Supports fuzzy project/task matching. Default task values is to sync all source tasks with a target task with "dev" in the name.
hubot remember a harvest migration from <project>[/<task>] to <project>[/<task>] at <harvest-subdomain>

# Perform a timesheet migration. Defaults to syncing the last 7 days.
hubot migrate [<num> days of ]<harvest-subdomain> harvest
```

Example hubot response after a migration:

```
Migrated 23.42 Project A hours to agency-1.
Migrated 2.42 Project B hours to agency-1.
Deleted 0.42 Project C hours from agency-1.
Project D is already in sync with agency-1.
Migrated 12.32 Project E hours to agency-2.
```

## License

Copyright (c) 2015 Aranja.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
