"""Validate full macOS acceptance provenance before writing acceptance receipts."""
import re


def verify_full_mac_run(run, jobs_response, source_metadata, artifact):
    source = source_metadata.get('sourceCommit')
    assert isinstance(source, str) and re.fullmatch(r'[0-9a-f]{40}', source)
    assert source_metadata.get('build') == 227
    assert source_metadata.get('sourceFrozen') is True, '227 source must be frozen first'
    assert source_metadata.get('published') is False
    assert run.get('head_sha') == source, 'Apple and Android frozen sources differ'
    assert run.get('event') == 'workflow_dispatch'
    assert run.get('path') == '.github/workflows/cross-platform-mobile.yml'
    assert run.get('status') == 'completed' and run.get('conclusion') == 'success'

    jobs = jobs_response.get('jobs')
    assert isinstance(jobs, list) and jobs_response.get('total_count') == len(jobs)
    apple = [job for job in jobs if job.get('name') == 'apple-app']
    assert len(apple) == 1, 'Exactly one latest full Apple job is required'
    job = apple[0]
    assert job.get('head_sha') == source and job.get('run_id') == run['id']
    assert job.get('status') == 'completed' and job.get('conclusion') == 'success'
    assert 'macos-26' in job.get('labels', []), 'Full acceptance requires macos-26'
    steps = job.get('steps', [])
    for name in ('Verify core parity and prepare native runtimes',
                 'Build and test the unsigned device app'):
        matches = [step for step in steps if step.get('name') == name]
        assert len(matches) == 1, name
        assert matches[0].get('status') == 'completed' and matches[0].get('conclusion') == 'success', name
    diagnostic = [step for step in steps
                  if step.get('name') == 'Diagnose the native simulator pipeline without accepting an IPA']
    assert all(step.get('conclusion') == 'skipped' for step in diagnostic)

    workflow_run = artifact.get('workflow_run', {})
    assert workflow_run.get('id') == run['id'] and workflow_run.get('head_sha') == source
    return {
        'passed': True,
        'sourceCommit': source,
        'runId': run['id'],
        'jobId': job['id'],
        'jobName': job['name'],
        'runnerLabels': job['labels'],
        'workflowPath': run['path'],
        'fullPreparationAndBuildStepsSucceeded': True,
        'artifactId': artifact['id'],
        'published': False,
    }
