# Job Attachments

## 3.1 What / Why Job Attachments?

Job attachments uses Deadline Cloud’s Queue configured S3 bucket as a [content-addressable storage](https://en.wikipedia.org/wiki/Content-addressable_storage), which creates a snapshot of the files used in your job submission in [asset manifests](https://github.com/aws-deadline/deadline-cloud/tree/mainline/src/deadline/job_attachments#asset-manifests), only uploading files that aren't already in S3. This saves you time and bandwidth when iterating on jobs. Only modified files will be uploaded to S3. Content Addressable Storage is modelled by hashing the contents of a file, and storing the file named as the hash value. Files containing the same binary content will result in the same hash, thus saving asset upload time on Job Submission. For example, a character model may be shared between Shots 1 and 2. When Shot 1 is submitted, the character model is hashed to the value `123abc` and uploaded to S3. When Shot 2 is submitted, Deadline's Job Attachments feature will detect the character model hash `123abc` is already on S3 to save upload time and bandwidth.

The core concept of Job Attachments is the Asset Manifest schema hosted on [Github](https://github.com/aws-deadline/deadline-cloud/blob/mainline/src/deadline/job_attachments/asset_manifests/schemas/2023-03-03.json). Take the following example.

```json
{
    "manifestVersion": "2023-03-03",
    "hashAlg": "xxh128",
    "paths": [
        {
            "hash": "20a443a514c8325c162ff3c5ca1d3161",
            "mtime": 1712972834000000,
            "path": "assets/input.png",
            "size": 5356783
        }
    ],
    "totalSize": 5356783
}
```

Every Asset Manifest contains the following attributes:

* `manifestVersion: “2023-03-03”`, Schema version designed to be extensible in the future.
* `hashAlg: “xx128”`, Hashing algorithm used to compute file hashes. At launch, only [xxh128](https://xxhash.com/) hashing is supported.
* `path: []` , A list of objects describing a content addressable file. Each file has the following properties.
    * `hash`: The file hash computed using `hashAlg` . This value is used as the storage file name.
    * `mtime`: The file time stamp of the file.
    * `path:` The local file path, and file name of a file.
    * `size:` The file size, in bytes.
* `totalSize: number`, the total number of bytes for all files associated with the manifest.



## 3.2 What is the Lifecycle of Job Attachments in Job Execution?

Job Attachments is involved in four phases of Job Submission, Execution to Downloading Outputs. In the context of this section, use of Storage Profiles is omitted for simplification. All assets are LOCAL to the job submission and data is exchanged using S3.

1. When a user submits a Job, either from DCC or CLI. 

   * When a Job submission process is started, a [Job Bundle](http://job_bundles/) is provided to Deadline Cloud’s Client side tooling. A Bundle’s [Asset References](https://github.com/aws-deadline/deadline-cloud-samples/tree/mainline/job_bundles#elements---asset-references) list the set of input files, and file paths required for job execution. Deadline cloud’s client software hashes each file as a content addressable element and uploads the data to S3. Input **Asset Manifests** are created, uploaded to S3 and associated with a job submission.

2. When a Worker Session is started, assets are required to render a particular Job-Session.

   * When an [AWS Deadline Cloud worker agent](https://github.com/aws-deadline/deadline-cloud-worker-agent/blob/release/docs/) starts working on a job-session with job attachments, it recreates the file system snapshot of step 1 in the worker agent session directory using the job’s Input **Asset Manifests**. Job Attachments downloads all inputs and structures the asset files exactly the same as local rendering.

3. When a Worker Session is completed, outputs are uploaded back to S3

   * When the Worker Agent completes a job-session, output folders annotated in [Asset References](https://github.com/aws-deadline/deadline-cloud-samples/tree/mainline/job_bundles#elements---asset-references) are recursively listed, and uploaded back to the S3 Content Addressable Storage. The content addressed output files of each Job-Session-Task is associated with an Output Manifest file. 

4. When the user downloads the output of a Job from DCC or CLI.

   * When the user wants to view the results of rendering a Job, the deadline client retrieves all output manifests of a Job,, Step or Task and downloads each output file from the Content Addressable storage back to the local workstation. 

In the following section, each of the four Job Attachments steps will be described in more detail.

## 3.3 Job Attachments at  Job creation

### 3.3.1 From Job Bundles

When a Deadline Cloud Queue is created, `jobAttachmentSettings` ([boto3](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/deadline/client/create_queue.html)) is a required property of the Create Queue request. When a Job is submitted, a Queue’s configured `jobAttachmentSettings` provides the `s3BucketName` and `rootPrefix` where Job Attachment files are uploaded. For each asset file in a bundle’s [assetsReferences](https://github.com/aws-deadline/deadline-cloud-samples/blob/mainline/job_bundles/README.md#elements---asset-references),  the file is hashed, uploaded to S3. Input Asset Manifest(s) are created for the Job Submission, uploaded to S3 and included as part of the [create_job](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/deadline/client/create_job.html) request.


### 3.3.2 What is the data layout on S3?

```bash
s3://my-storage-bucket
 -> PrefixFolder
    -> Data
      -> 20a443a514c8325c162ff3c5ca1d3161.xxh128
      -> aed61cd2df405c0e4fa3d56a07fd890a.xxh128
      -> 1ca097621ec5c100569ff7f53e64031c.xxh128
      -> ...
    -> Manifests
      -> farm-00000000000000000000000000000000
        -> queue-11111111111111111111111111111111
          -> Inputs
            -> 12345678123456781234567812345678_input
            -> abcdef01abcdef01abcdef01abcdef01_input
```

Lets dive into the actual layout of the Content Address storage on Job submissions. In this example, the `s3BucketName` is configured to `s3://my-storage-bucket`, and `rootPrefix` is configured to `PrefixFolder`. The root path of this Content Addressable store is `s3://my-storage-bucket/PrefixFolder`. Within this root, there are two folders:

* `Data`, this is where all the data files are stored. Note in this example there are 3 files with a 32 character hash as name, and extension `xxh128` (Hashing algorithm). 
* `Manifests` , this folder is nested and organized in the form `/{farm-id}/{queue-id}/Inputs/` . All Input Asset Manifest from a Job, Queue are stored in this folder. Input Manifests are named with a 32 character hash concatenated with `_input`.  Notice this folder structure containing Farm and Queue ID. This folder structure is designed to allow sharing of the S3 Content Address Storage across Queues and Farms. 

```json
# Contents of 12345678123456781234567812345678_input
{
    "hashAlg": "xxh128",
    "manifestVersion": "2023-03-03",
    "paths": [
        {
            "hash": "20a443a514c8325c162ff3c5ca1d3161",
            "mtime": 1712972834000000,
            "path": "assets/MP4/Trailer1080.mp4",
            "size": 5356783
        },
        {
            "hash": "aed61cd2df405c0e4fa3d56a07fd890a",
            "mtime": 1712967372000000,
            "path": "assets/SRC/watermark.png",
            "size": 26205
        },
        {
            "hash": "1ca097621ec5c100569ff7f53e64031c",
            "mtime": 1712977780000000,
            "path": "assets/SRC/Balrog.nk",
            "size": 7104
        }
    ],
    "totalSize": 5390092
}
```

The Input Manifest utilize the Asset Manifest specification to enumerate input files. As an example, the asset manifest `12345678123456781234567812345678_input` models a job with 3 input files, totalling 5390092 bytes. 

For example, file `assets/MP4/Trailer1080.mp4` hashes to `20a443a514c8325c162ff3c5ca1d3161` . In the content addressable store, notice how `20a443a514c8325c162ff3c5ca1d3161.xxh128` exists in the `Data` directory. The input manifest path object provides the mapping between input asset file-path, and the associated hash named file in the Content Addressable Data folder. Two other input files are presented for reference.

## 3.4 Job Attachments During Session Execution

Once a job is submitted to Deadline Cloud, workers are assigned sessions representing Tasks within a single Step of a Job. Each Session is comprised of Input Asset synchronization, Conda Environment Bootstrapping [Optional], one or more task runs and finally Output synchronization and cleanup. In this section, each step involved with Job Attachments will be explored.

### 3.4.1 Input Asset Synchronization

```bash
# On the worker:
/sessions/OpenJD/{session temp dir}
  -> /assetroot-{hash}/
    -> assets/MP4/Trailer1080.mp4 (20a443a514c8325c162ff3c5ca1d3161.xxh128)
    -> assets/SRC/watermark.png.  (aed61cd2df405c0e4fa3d56a07fd890a.xxh128)
    -> assets/SRC/Balrog.nk       (1ca097621ec5c100569ff7f53e64031c.xxh128)
  -> /assetroot-{hash2}/
    -> files/abc.png
    -> files/123.exr
```

Input Asset Synchronization is the first step of a session. In this session action, a Job’s inputs are copied from the Content Address Storage to the worker. Continuing from the example in the prior section, the Input manifest consists of 3 files. On the worker, each asset manifest’s file is copied to a unique folder named `assetroot-{hash}`. In the example, content file `20a443a514c8325c162ff3c5ca1d3161.xx128hash` is downloaded to the asset folder with the original path `/assets/MP4/Trailer1080.mp4`. Notice how the original job submission folder structure is replicated to the worker. 

### 3.4.2 Worker Job Attachments Output 

A) Worker Output

```bash
/sessions/OpenJD/{session temp dir}/asset-root-{hash}/
  -> output/`output_0001.png`
```

B) Output Manifest - abcdef01abcdef01abcdef01abcdef01_output

```json
{
    "hashAlg": "xxh128",
    "manifestVersion": "2023-03-03",
    "paths": [
        {
            "hash": "623c01f620299050f3fd828bbd0cac9e",
            "mtime": 1712283778226271,
            "path": "output/output_0001.png",
            "size": 7986453
        }
    ],
    "totalSize": 7986453
}
```

C) S3 Data Layout

```bash
S3://my-storage-bucket
 -> Prefix Folder
    -> Data
      -> 623c01f620299050f3fd828bbd0cac9e.xxh128
    -> Manifests
      -> farm-00000000000000000000000000000000
        -> queue-11111111111111111111111111111111
          -> job-2222222222222222222222222222222222
            -> step-333333333333333333333333333333333
              -> task-444444444444444444444444444444444
                -> {time}-session-action-55555555555555555555555555555555-1
                   -> abcdef01abcdef01abcdef01abcdef01_output
```

In the last step of session execution on a worker, outputs of the session are saved back to the Content Address Storage. Job Attachments will recursively list and find all files stored in outputs paths defined by `dataFlow` `OUT,INOUT` of the job template and outputs defined by a bundle’s  `assetReferences`. Similar to Input files, Job Attachments is used to store output files as content addressed storage. For example, the example explored thus far had and output file `/output/output_0001.png` , located in the file path as depicted in A) above. Job Attachments will first hash the file `output_0001.png`, computing `623c01f620299050f3fd828bbd0cac9e` as the hash. The output file is then uploaded to S3 in the Data directory, with file name  `623c01f620299050f3fd828bbd0cac9e.xxh128` . A corresponding Output Asset Manifest is generated to model the output files and hash relationship (B). The Output Manifest is uploaded to `Manifests` folder but stored nested under a folder structure representing the Session’s job lineage. The full file structure representing the output file and manifest are presented in C).

### 3.4.3 Job Attachments for step-step dependencies

A) Example Step-Step template:

```yaml
name: Step-Step Dependency Test
specificationVersion: 'jobtemplate-2023-09'
steps:
- name: A
    ....
- name: B
  dependencies:
  - dependsOn: A # This means Step B depends on Step A
     ....
- name: C
  dependencies: # This means Step B depends on Step A and Step B
  - dependsOn: A
  - dependsOn: B 
     ....   
```

B) Step - Step dependency storage reference

```bash
S3://my-storage-bucket
 -> Prefix Folder
    -> Data
      -> aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.xxh128
      -> bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.xxh128
    -> Manifests
      -> farm-00000000000000000000000000000000
        -> queue-11111111111111111111111111111111
          -> job-2222222222222222222222222222222222
            -> step-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
              -> task-444444444444444444444444444444444
                -> {time}-session-action-55555555555555555555555555555555-1
                   -> abcdef01abcdef01abcdef01abcdef01_output
            -> step-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
              -> task-777777777777777777777777777777777
                -> {time}-session-action-88888888888888888888888888888888-1
                   -> qwerty01qwerty01qwerty01qwerty01_output
```

Deadline Cloud supports [Step-Step Dependencies](https://docs.aws.amazon.com/deadline-cloud/latest/userguide/jobs-scheduling.html#jobs-scheduling-dependencies), where steps within a Job can be chained as dependencies to form an execution Control Flow Graph. Lets take an example provided by the Job template in A). Step A has no dependencies and is executed first. Step B depends on Step A’s output. Step C depends on both Step A and B’s output. From the prior section, outputs of each step are stored to S3 and referenced via an Output Manifest. For readability, the has file output of Steps A and B are named “`aaaa...xxhash`” and “`bbb....xxhash`” When the worker executes Step B, the output manifests of Step A are listed from S3 then all content addressed data are downloaded to the session directory. All outputs of Step A are downloaded by performing a S3 list object with matching `s3://my-storage-bucket/PrefixFolder/Manifest/farm-000.../queue-111..../job-2222/step-AAA.../*/*_output`. In this example,  the output CAS file `aaa....xxh128` is downloaded. Similarly, when Step C is executed, the output manifests for Step A and Step B are similarly listed. Files `aaa....xxh128` and `bbb....xxh128` are downloaded for session execution.

Job-to-Job dependencies is currently not supported for Deadline Cloud.

## 3.5.0 Job Attachments Output Download 

```bash
S3://my-storage-bucket
 -> Prefix Folder
    -> Data
      -> 623c01f620299050f3fd828bbd0cac9e.xxh128
    -> Manifests
      -> farm-00000000000000000000000000000000
        -> queue-11111111111111111111111111111111
          -> job-2222222222222222222222222222222222
            -> step-333333333333333333333333333333333
              -> task-444444444444444444444444444444444
                -> {time}-session-action-55555555555555555555555555555555-1
                   -> abcdef01abcdef01abcdef01abcdef01_output
                -> {time2}-session-action-55555555555555555555555555555555-1
                   -> qwerty01qwerty01qwerty01qwerty01_output
```

Finally, after a Job is successfully completed on Deadline Cloud, users will want to download the output back to their workstation for review. Job Attachments offers a CLI command (`deadline job download-output`) to download outputs at Job, Step or Task level. The CLI command first lists all Output Manifest objects ending with `_output`, located under the S3 folder structure prefixed at job, step, task IDs. Next, all output files contained in output manifests are downloaded back to the user’s workstation and remapped via the output folder structure. Note; for any tasks that are executed multiple times from retries, or manual re-execution, the Job Attachments download feature will filter and download only the most recent output. This is illustrated in the example above. If a task is executed twice, where `time2` > `time.` Only the output from `time2` will be downloaded.

The Deadline Cloud Monitor also provides an easy to use Download [feature](https://docs.aws.amazon.com/deadline-cloud/latest/userguide/download-finished-output.html) to easily execute the download CLI command for Job, Step or Task.