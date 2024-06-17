# HelloID-Task-SA-Source-HelloID-AccountSearch

## Prerequisites

- [ ] _HelloID_ environment.
- [ ] _HelloID_ Service Automation agent (cloud or on-prem).
- [ ] Access to the _HelloID_ API.
  - [ ] API Key
  - [ ] API Secret

## Description

This code snippet executes the following tasks:

1. Imports the ActiveDirectory module.
2. Define a search query `$HelloIDUserSearchFilter` based on the search parameter `$datasource.searchUser`
3. Retrieve the HelloID users using the `Get all users` API with a paging of 1000.

> The query property **search** searches for users via contains in following fields: Firstname, Lastname, Username, Contact email [See the HelloID Docs page](https://apidocs.helloid.com/docs/helloid/041932dd2ca73-get-all-users)

1. Return a hash table for each user account using the `Write-Output` cmdlet.

> To view an example of the data source output, please refer to the JSON code pasted below.

```json
{
    "searchUser": "James"
}
```