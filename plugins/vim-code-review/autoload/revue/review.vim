vim9script

# Provider entry point into the same persistent-card session UI as :Review.
export def OpenReview(snapshot: dict<any>, Host: func, file_idx: number = -1): string
  return revue#backend#Open({id: 'provider-v1', connection: '', review: snapshot.key,
    snapshot: snapshot, Request: Host, legacy_key: snapshot.key}, file_idx)
enddef
