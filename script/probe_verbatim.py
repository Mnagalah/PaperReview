"""A bounded, local-only prompt experiment on the synthetic fixture, not a benchmark."""
import base64,json,pathlib,time,urllib.request
records=list(pathlib.Path('/tmp/PaperReview-QA-20261103').glob('*/record.json'))
folder=next(f.parent for f in records if json.loads(f.read_text())['title']=='synthetic-essay')
image=base64.b64encode((folder/'enhanced.png').read_bytes()).decode()
prompt='Text Recognition:\nTranscribe exactly as written. Preserve all original spelling and grammar errors. Do not correct, complete or improve any word.'
body=dict(model='minicpm-ocr',stream=False,messages=[dict(role='user',content=[dict(type='image_url',image_url=dict(url='data:image/png;base64,'+image)),dict(type='text',text=prompt)])],max_tokens=4096,temperature=0.01,top_p=0.001,top_k=1,repeat_penalty=1)
request=urllib.request.Request('http://127.0.0.1:18499/v1/chat/completions',data=json.dumps(body).encode(),headers={'Content-Type':'application/json'})
start=time.monotonic()
with urllib.request.urlopen(request,timeout=120) as response: result=json.load(response)
result['probe_seconds']=time.monotonic()-start
result['probe_prompt']=prompt
pathlib.Path('docs/verification/verbatim-prompt-probe.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
print(result['choices'][0]['message']['content'])
