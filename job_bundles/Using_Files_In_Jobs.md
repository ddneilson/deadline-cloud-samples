# Using Files in Your Jobs

Many of the jobs that you submit to AWS Deadline Cloud will have input and output in the form
of files. Your input files and output directories may be located on a combination of your shared filesystems
and local drive. Your jobs require a way to locate the content in those locations. Deadline Cloud's
[job attachments](https://docs.aws.amazon.com/deadline-cloud/latest/userguide/storage-job-attachments.html) and
[storage profiles](https://docs.aws.amazon.com/deadline-cloud/latest/userguide/storage-shared.html) features work
in concert to help your jobs locate the files that they needs.

Deadline Cloud's job attachments feature helps you move files to your worker hosts from filesystem locations on your
workstation that are not available on your worker hosts, and vice versa. It shuttles files between hosts using
[Amazon S3](https://aws.amazon.com/pm/serv-s3/) as an intermediary. Job attachments can be enabled individually
on each of your queues to make it available to jobs in those queues.

You use Deadline Cloud's storage profiles to model the layout of shared filesystem locations on your workstation and
worker hosts. This helps your jobs locate shared files and directories when their locations differ between your workstation
and worker hosts, such as in cross-platform setups with Windows based workstations and Linux based worker hosts.
Storage profile's model of your filesystem configuration is also leveraged by job attachments to identify which files
it needs to shuttle between hosts through Amazon S3.

Note that if you are not using Deadline Cloud's job attachments feature, and you do not need to remap file and
directory locations between workstations and worker hosts then you do not need to model your fileshares with
storage profiles.

## 1. Sample Project Infrastructure

For the purpose of demonstration, consider the following hypothetical infrastructure that is set up to
support two separate projects. To follow along, set up a farm, fleet, and two queues using the console for
AWS Deadline Cloud and then be sure to delete these resources when you are done:

1. [Farm](https://docs.aws.amazon.com/deadline-cloud/latest/userguide/farms.html#create-farm):
    1. Named: `AssetDemoFarm`
    2. All other settings default.
2. Two [queues](https://docs.aws.amazon.com/deadline-cloud/latest/userguide/create-queue.html):
    1. The first is for jobs for only the first of the two projects:
        1. Named: `Q1`.
        2. Job attachments: Create a new Amazon S3 bucket.
        3. Association with customer-managed fleets: Enabled.
        4. Run as user configuration: `jobuser` as both the user name and group name for POSIX credentials.
        5. Queue service role: Create a new role the name `AssetDemoFarm-Q1-Role`
        6. Default Conda queue environment: Unselect the checkbox for the default queue environment.
        7. All other settings default.
    2. The second is for jobs for only the second of the two projects:
        1. Named: `Q2`.
        2. Job attachments: Create a new Amazon S3 bucket.
        3. Association with customer-managed fleets: Enabled.
        4. Run as user configuration: `jobuser` as both the user name and group name for POSIX credentials.
        5. Queue service role: Create a new role with the name `AssetDemoFarm-Q2-Role`
        6. Default Conda queue environment: Unselect the checkbox for the default queue environment.
        7. All other settings default.
3. A single customer-managed [Fleet](https://docs.aws.amazon.com/deadline-cloud/latest/userguide/create-a-cmf.html)
   that will run the jobs from both queues:
    1. Named: `Fleet`
    2. Fleet type: Customer-managed.
    3. Fleet service role: Create a new role with a name of your choosing. e.g. `AssetDemoFarm-Fleet-Role`
    4. All other settings default. Importantly, do not associate the fleet with any queues at this time.

This hypothetical infrastructure has three filesystem locations that are shared between hosts via network fileshares. We
refer to these locations by the following names:

1. `FSComm` - Containing input job assets that are common to both projects.
2. `FS1` - Containing input and output job assets for project 1.
3. `FS3` - Containing input and output job assets for project 2.

The infrastructure has three workstation configurations that we'll refer to as `WS1`, `WS2`, and `WSAll`:

1. `WSAll` - A Linux-based workstation set up for developers to assist with all projects. The shared filesystem locations are:
    1. `FSComm`: `/shared/common`
    2. `FS1`: `/shared/projects/project1`
    3. `FS2`: `/shared/projects/project2`
2. `WS1` - A Windows-based workstation set up to work on only project 1. The shared filesystem locations are:
    1. `FSComm`: `S:\`
    2. `FS1`: `Z:\`
    3. `FS2`: Not available
3. `WS2` - A MacOS-based workstation set up to work on only project 2. The shared filesystem locations are:
    1. `FSComm`: `/Volumes/common`
    2. `FS1`: Not available
    3. `FS2`: `/Volumes/projects/project2`

Finally, we'll refer to the fleet's worker configuration as `WorkerCfg`. The shared filesystem locations for `WorkerCfg` are:

1. `FSComm`: `/mnt/common`
2. `FS1`: `/mnt/projects/project1`
3. `FS2`: `/mnt/projects/project2`

Note that you do not need to set up any shared filesystems, workstations, or workers that match this configuration to follow along.
We will be modeling these shared locations, but they do not need to exist to be modeled.

## 2. Storage Profiles and Path Mapping

You use AWS Deadline Cloud's storage profiles to model the filesystems on your workstation and worker hosts.
Each storage profile describes the operating system and filesystem layout of one of your system configurations.
This chapter describes how you can use storage profiles to model the filesystem configurations of your hosts so that
Deadline Cloud can automatically generate path mapping rules for your jobs, and how those path mapping rules
are generated from your storage profiles.

When you submit a job to Deadline Cloud you can optionally provide a storage profile id for that job. This storage
profile is the submitting workstation's profile and describes the filesystem configuration that the file paths in
the job's input and output file references are written for. 

You can also associate a storage profile with a [customer managed fleet](https://docs.aws.amazon.com/deadline-cloud/latest/userguide/manage-cmf.html).
That storage profile describes the filesystem configuration of all worker hosts in that fleet. If you have
workers with different filesystem configurations, then those workers must be assigned to different fleets in your
farm. Storage profiles are not supported in [service managed fleets](https://docs.aws.amazon.com/deadline-cloud/latest/userguide/smf-manage.html).

Path mapping rules describe how paths should be remapped from how they are specified in the job to the
path's actual location on a worker host. Deadline Cloud compares the filesystem configuration described
in a job's storage profile with the storage profile of the fleet that is running the job to derive these
path mapping rules.

### 2.1. Modeling Your Shared Filesystem Locations with Storage Profiles

A storage profile models the filesystem configuration of one of your host configurations. There are four different host configurations in
the [sample project infrastructure](#1-sample-project-infrastructure), so we will create a separate storage profile for each. You can create
a storage profile with the [CreateStorageProfile API](https://docs.aws.amazon.com/deadline-cloud/latest/APIReference/API_CreateStorageProfile.html),
[AWS::Deadline::StorageProfile](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-deadline-storageprofile.html)
[AWS CloudFormation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/Welcome.html) resource, or 
[AWS Console](https://docs.aws.amazon.com/deadline-cloud/latest/userguide/storage-shared.html#storage-profile). 

A Storage Profile is made up of a list of filesystem locations that each tell Deadline Cloud the location and type of a filesystem
location that is relevant for jobs submitted from or run on a host. A storage profile should only model the locations that are
relevant for jobs. For example, the shared `FSComm` location is located on workstation `WS1` at `S:\`, so the corresponding
filesystem location is:

```json
{
    "name": "FSComm",
    "path": "S:\\",
    "type": "SHARED"
}
```

Now, create the storage profile for workstation configurations `WS1`, `WS2`, and `WS3` and the worker configuration `WorkerCfg`
using the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html) in
[AWS CloudShell](https://docs.aws.amazon.com/cloudshell/latest/userguide/welcome.html):

```bash
# Change the value of FARM_ID to your farm's identifier
FARM_ID=farm-00112233445566778899aabbccddeeff

aws deadline create-storage-profile --farm-id $FARM_ID \
  --display-name WSAll \
  --os-family LINUX \
  --file-system-locations \
  '[
      {"name": "FSComm", "type":"SHARED", "path":"/shared/common"},
      {"name": "FS1", "type":"SHARED", "path":"/shared/projects/project1"},
      {"name": "FS2", "type":"SHARED", "path":"/shared/projects/project2"}
  ]'

aws deadline create-storage-profile --farm-id $FARM_ID \
  --display-name WS1 \
  --os-family WINDOWS \
  --file-system-locations \
  '[
      {"name": "FSComm", "type":"SHARED", "path":"S:\\"},
      {"name": "FS1", "type":"SHARED", "path":"Z:\\"}
   ]'

aws deadline create-storage-profile --farm-id $FARM_ID \
  --display-name WS2 \
  --os-family MACOS \
  --file-system-locations \
  '[
      {"name": "FSComm", "type":"SHARED", "path":"/Volumes/common"},
      {"name": "FS2", "type":"SHARED", "path":"/Volumes/projects/project2"}
  ]'

aws deadline create-storage-profile --farm-id $FARM_ID \
  --display-name WorkerCfg \
  --os-family LINUX \
  --file-system-locations \
  '[
      {"name": "FSComm", "type":"SHARED", "path":"/mnt/common"},
      {"name": "FS1", "type":"SHARED", "path":"/mnt/projects/project1"},
      {"name": "FS2", "type":"SHARED", "path":"/mnt/projects/project2"}
  ]'
```

It is essential that the file system locations in your storage profiles are referenced using the same values
for the `name` property across all storage profiles in your farm. Deadline Cloud compares these names to determine whether
filesystem locations from different storage profiles are referencing the same location when generating path mapping rules.

### 2.2. Configuring Storage Profiles for Fleets

A customer-managed fleet's configuration can include a storage profile that models the filesystem locations on all
workers in that fleet. The host filesystem configuration of all workers in a fleet must match their fleet's storage
profile. Workers with different filesystem configurations must be in separate fleets.

Update your fleet's configuration to set its storage profile to the `WorkerCfg` storage profile using the
[AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html) in
[AWS CloudShell](https://docs.aws.amazon.com/cloudshell/latest/userguide/welcome.html):

```bash
# Change the value of FARM_ID to your farm's identifier
FARM_ID=farm-00112233445566778899aabbccddeeff
# Change the value of FLEET_ID to your fleet's identifier
FLEET_ID=fleet-00112233445566778899aabbccddeeff
# Change the value of WORKER_CFG_ID to your storage profile named WorkerCfg
WORKER_CFG_ID=sp-00112233445566778899aabbccddeeff

FLEET_WORKER_MODE=$( \
  aws deadline get-fleet --farm-id $FARM_ID --fleet-id $FLEET_ID \
  | jq '.configuration.customerManaged.mode' \
)
FLEET_WORKER_CAPABILITIES=$( \
  aws deadline get-fleet --farm-id $FARM_ID --fleet-id $FLEET_ID \
  | jq '.configuration.customerManaged.workerCapabilities' \
)

aws deadline update-fleet --farm-id $FARM_ID --fleet-id $FLEET_ID \
  --configuration \
  "{
    \"customerManaged\": {
      \"storageProfileId\": \"$WORKER_CFG_ID\",
      \"mode\": $FLEET_WORKER_MODE,
      \"workerCapabilities\": $FLEET_WORKER_CAPABILITIES
    }
  }"
```

### 2.3. Storage Profiles for Queues

A queue's configuration includes a list of case-sensitive names of the shared filesystem locations that jobs submitted to the queue
require access to. In the sample infrastructure, jobs submitted to queue `Q1` require filesystem locations `FSComm` and `FS1`, and
jobs submitted to queue `Q2` require filesystem locations `FSComm` and `FS2`. Update the queue's configurations to require these
filesystem locations:

```bash
# Change the value of FARM_ID to your farm's identifier
FARM_ID=farm-00112233445566778899aabbccddeeff
# Change the value of QUEUE1_ID to queue Q1's identifier
QUEUE1_ID=queue-00112233445566778899aabbccddeeff
# Change the value of QUEUE2_ID to queue Q2's identifier
QUEUE2_ID=queue-00112233445566778899aabbccddeeff

aws deadline update-queue --farm-id $FARM_ID --queue-id $QUEUE1_ID \
  --required-file-system-location-names-to-add FSComm FS1

aws deadline update-queue --farm-id $FARM_ID --queue-id $QUEUE2_ID \
  --required-file-system-location-names-to-add FSComm FS2
```

Note that if a queue has any required filesystem locations, then that queue cannot be associated with a
[service-managed fleet](https://docs.aws.amazon.com/deadline-cloud/latest/userguide/smf-manage.html) because
that fleet has no way to mount your shared filesystems.

A queue's configuration also includes a list of allowed storage profiles that applies to jobs submitted to
and fleets associated with that queue. Only storage profiles that define filesystem locations for all of the required filesystem
locations of that queue are allowed in the queue's list of allowed storage profiles. 

Submitting a job with a storage profile other than one in the list of allowed storage profiles for a queue will fail. A job with
no storage profile can always be submitted to a queue.
The workstation configurations labeled `WSAll` and `WS1` both have the required filesystem locations (`FSComm` and `FS1`) for queue `Q1`
and need to be allowed to submit jobs to the queue. Similarly, workstation configurations `WSAll` and `WS2` meet the requirements for 
queue `Q2` and need to be allowed to submit jobs to that queue. So, update both queue's configurations to allow jobs to be submitted
with these storage profiles:

```bash
# Change the value of WSALL_ID to the identifier of the WSALL storage profile
WSALL_ID=sp-00112233445566778899aabbccddeeff
# Change the value of WS1 to the identifier of the WS1 storage profile
WS1_ID=sp-00112233445566778899aabbccddeeff
# Change the value of WS2 to the identifier of the WS2 storage profile
WS2_ID=sp-00112233445566778899aabbccddeeff

aws deadline update-queue --farm-id $FARM_ID --queue-id $QUEUE1_ID \
  --allowed-storage-profile-ids-to-add $WSALL_ID $WS1_ID

aws deadline update-queue --farm-id $FARM_ID --queue-id $QUEUE2_ID \
  --allowed-storage-profile-ids-to-add $WSALL_ID $WS2_ID
```

If you were to try to add the `WS2` storage profile to the list of allowed storage profiles for queue `Q1` then it would fail:

```bash
$ aws deadline update-queue --farm-id $FARM_ID --queue-id $QUEUE1_ID \
  --allowed-storage-profile-ids-to-add $WS2_ID

An error occurred (ValidationException) when calling the UpdateQueue operation: Storage profile id: sp-00112233445566778899aabbccddeeff does not have required file system location: FS1
```

This is because the `WS2` storage profile does not contain a definition for the filesystem location named `FS1` that queue `Q1` requires.

Associating a fleet that is configured with a storage profile that is not in the queue's list of allowed storage profiles will also fail. For example:

```bash
$ aws deadline create-queue-fleet-association --farm-id $FARM_ID \
   --fleet-id $FLEET_ID \
   --queue-id $QUEUE1_ID

An error occurred (ValidationException) when calling the CreateQueueFleetAssociation operation: Mismatch between storage profile ids.
```

So, add the storage profile named `WorkerCfg` to the lists of allowed storage profiles for both queue `Q1` and queue `Q2` and then associate
the fleet with these queues so that workers in the fleet can run jobs from both queues.

```bash
# Change the value of FLEET_ID to your fleet's identifier
FLEET_ID=fleet-00112233445566778899aabbccddeeff
# Change the value of WORKER_CFG_ID to your storage profile named WorkerCfg
WORKER_CFG_ID=sp-00112233445566778899aabbccddeeff

aws deadline update-queue --farm-id $FARM_ID --queue-id $QUEUE1_ID \
  --allowed-storage-profile-ids-to-add $WORKER_CFG_ID

aws deadline update-queue --farm-id $FARM_ID --queue-id $QUEUE2_ID \
  --allowed-storage-profile-ids-to-add $WORKER_CFG_ID

aws deadline create-queue-fleet-association --farm-id $FARM_ID \
  --fleet-id $FLEET_ID \
  --queue-id $QUEUE1_ID

aws deadline create-queue-fleet-association --farm-id $FARM_ID \
  --fleet-id $FLEET_ID \
  --queue-id $QUEUE2_ID
```

### 2.4. Deriving Path Mapping Rules from Storage Profiles

Path mapping rules describe how paths should be remapped from how they are specified in the job to the
path's actual location on a worker host. When a task from a job is running on a worker, the storage
profile that the job was submitted with is compared to the storage profile of the worker's fleet to
derive the path mapping rules that are given to the task. 

A mapping rule is created for each of the required filesystem locations in the queue's configuration.
For instance, a job submitted with the `WSAll` storage profile to queue `Q1` in the sample infrastructure
will have the path mapping rules:

1. `FSComm`: `/shared/common -> /mnt/common`
2. `FS1`: `/shared/projects/project1 -> /mnt/projects/project1`

Rules are created for the `FSComm` and `FS1` filesystem locations, but not the `FS2`
filesystem location even though both the `WSAll` and `WorkerCfg` storage profiles define filesystem
locations for `FS2`. This is because queue `Q1`'s list of required filesystem locations is `["FSComm", "FS1"]`.

You can confirm the path mapping rules that are available to jobs submitted with a particular
storage profile by submitting a job that prints out 
[Open Job Description's path mapping rules file](https://github.com/OpenJobDescription/openjd-specifications/wiki/How-Jobs-Are-Run#path-mapping),
and then reading the session log after the job has completed:

```bash
# Change the value of FARM_ID to your farm's identifier
FARM_ID=farm-00112233445566778899aabbccddeeff
# Change the value of QUEUE1_ID to queue Q1's identifier
QUEUE1_ID=queue-00112233445566778899aabbccddeeff
# Change the value of WSALL_ID to the identifier of the WSALL storage profile
WSALL_ID=sp-00112233445566778899aabbccddeeff

aws deadline create-job --farm-id $FARM_ID --queue-id $QUEUE1_ID \
  --priority 50 \
  --storage-profile-id $WSALL_ID \
  --template-type JSON --template \
  '{
    "specificationVersion": "jobtemplate-2023-09",
    "name": "DemoPathMapping",
    "steps": [
      {
        "name": "ShowPathMappingRules",
        "script": {
          "actions": {
            "onRun": {
              "command": "/bin/cat",
              "args": [ "{{Session.PathMappingRulesFile}}" ]
            }
          }
        }
      }
    ]
  }'
```

Note that if you are using the [Dealine Cloud CLI](https://pypi.org/project/deadline/) to submit jobs that its
configuration's `settings.storage_profile_id` setting dictates the storage profile that jobs submitted with
the CLI will have. To submit jobs with the `WSAll` storage profile, set:

```bash
deadline config set settings.storage_profile_id $WSALL_ID
```

To run a customer-managed worker as though it was running in the sample infrastructure, follow the
directions from the [Deadline Cloud User Guide](https://docs.aws.amazon.com/deadline-cloud/latest/userguide/run-worker.html)
on running a worker within AWS CloudShell. If you have run those instructions before, then delete the `~/demoenv-logs`
and `~/demoenv-persist` directories first. Also, set the values of the `DEV_FARM_ID` and `DEV_CMF_ID` environment variables
that the directions reference as follows before doing so:

```bash
DEV_FARM_ID=$FARM_ID
DEV_CMF_ID=$FLEET_ID
```

Once the job is run, look at the job's log file to see the path mapping rules printed out:

```bash
cat demoenv-logs/${QUEUE1_ID}/*.log
...
2024-07-14 20:46:09,446 INFO {"version": "pathmapping-1.0", "path_mapping_rules": [{"source_path_format": "POSIX", "source_path": "/shared/projects/project1", "destination_path": "/mnt/projects/project1"}, {"source_path_format": "POSIX", "source_path": "/shared/common", "destination_path": "/mnt/common"}]}
...
```

Reformatting for readability, this contains remaps for both the `FS1` and `FSComm` filesystems as expected:

```json
{
    "version": "pathmapping-1.0",
    "path_mapping_rules": [
        {
            "source_path_format": "POSIX",
            "source_path": "/shared/projects/project1",
            "destination_path": "/mnt/projects/project1"
        },
        {
            "source_path_format": "POSIX",
            "source_path": "/shared/common",
            "destination_path": "/mnt/common"
        }
    ]
}
```

Submit jobs with different storage profiles to see the changes in the path mapping rules.

## 3. Job Attachments

Link: https://docs.aws.amazon.com/deadline-cloud/latest/userguide/storage-job-attachments.html

- Job attachments is a feature for making files that are not in shared filesystem locations available for your jobs, and making
  the file outputs of a job available when they are not written to a shared filesystem location. 
- Essential for service-managed fleets, since there are no filesystem locations that are shared between hosts. Useful
  for customer-managed fleets for things like job-specific script files, one-off input files or local edits that you do not want
  to store on a shared filesystem.
- It manages shuttling files betweeen hosts by using Amazon S3 as an intermediary; storing the objects in S3 in a way that
  eliminates the need to re-upload a file if its content exactly matches a previously uploaded file.

When using a job bundle to submit a job, either using the [Deadline Cloud CLI](https://pypi.org/project/deadline/)
or a Deadline Cloud submitter, the implementation of the job attachments feature uses a job's storage profile
and the queue's required filesystem locations to identify the input files that will not be available on a worker host, and
thus should be uploaded to Amazon S3 as part of job submission. Similarly, the fleet's storage profile also helps the job attachments
feature identify which of a job's output files are in locations that will not be available on your workstation and need to
be uploaded to Amazon S3.

### 3.1. Submitting Files with a Job

- In CloudShell, using the worker running in a separate tab.

- `git clone https://github.com/aws-deadline/deadline-cloud-samples.git`
- `cp -r deadline-cloud-samples/job_bundles/job_attachments_devguide ~/`

- Highlight the ScriptFile job parameter, it's default value being relative to the bundle's directory, and dataFlow IN.
  What that means for job attachments.
- Configure deadline CLI for farm & Q1. Submit the job using the deadline CLI. Point out that the script file was uploaded.
- `deadline job get` to show the manifest.
- Show layout of objects in S3.
- Modify the script file to print the contents of the path mapping rules file (pass an arg that is the file location & cat it)
- Resubmit the job. Point out that the script file uploaded because it changed.
- Show that job attachments adds to the list of path mapping rules.

- Refer to Open Job Description wiki page on creating jobs; section on path mapping for additional information.

- Location in asset_references needing to be communicated via a path-type parameter to get automatic path mapping, else
  use the path mapping rules file.
  - Add an asset_references file that adds an input file that's in /tmp; any contents.
  - Submit the job.
  - Show the path mapping rules that result. Talk about the location of the new file not being available in the
    job template.

- Something about asset roots? How they're determined?

#### 3.1.1. Input Files with Storage Profiles

- Make one of the `WSAll` dirs and add a file to it. 
- Add that file to the asset references input files list.
- Submit the job, and show that the newly added file is not uploaded.

- Copy the script file outside of the bundle dir (e.g. to /tmp/job_inputs). Show that there's a permissions prompt when submitting.
- Then set LOCAL filesystem location. Submit to demonstrate that the prompt no longer appears.

- Do a submission with no storage profile. All files are uploaded via job attachments.

- Need to include something customer-facing on why this is the way that it is.

### 3.2. Getting Output Files from a Job

- Extend the example bundle to add an output directory. dataFlow OUT job parameter; objectType DIR.
- Modify the script to also write a file to the output dir (pass in the outdir as an arg).
- Submit the job.
- Mention the path mapping rule being added for the output dir.
- Show the file that is uploaded to S3, the current S3 object layout, the manifest file, and how to get those using the deadline CLI.

### 3.3. Using Files Output from a Step in a Dependent Step

- Extend example to add a dependent step. Have that step write the sha256sum, or some such, of the prev step's
  output file to a new file.
- Submit the job. Show the dependent step fetching the prev step's output file.

-----

# Notes

## Job Attachments

So... what are the essential things that someone using Deadline Cloud needs to understand about JA? I think that it's:
- How does JA identify which files to upload during submission.
- How does JA identify which files are uploaded to s3 as outputs.
- How does JA connect the JA-outputs of one step to another step in the same job.


Within that, a little information about creation of the manifest file (so that they can understand how to use CreateJob directly), and how objects are layed out in S3.