"""Matched-input OCR precision check. Uses only the already running local model."""
import base64,json,pathlib,time,urllib.request
cases=[('same_page',pathlib.Path('/tmp/PaperReview-QA-v2-20261103/4E504A42-DBEB-4988-A24E-13E4E099E8DC/enhanced.png')),('same_word',pathlib.Path('docs/verification/word-original.png'))]
results=[]
for name,path in cases:
 image=base64.b64encode(path.read_bytes()).decode()
 body=dict(model='minicpm-ocr',stream=False,messages=[dict(role='user',content=[dict(type='image_url',image_url=dict(url='data:image/png;base64,'+image)),dict(type='text',text='Text Recognition:')])],max_tokens=4096,temperature=.01,top_p=.001,top_k=1,repeat_penalty=1)
 req=urllib.request.Request('http://127.0.0.1:18499/v1/chat/completions',data=json.dumps(body).encode(),headers={'Content-Type':'application/json'})
 start=time.monotonic()
 with urllib.request.urlopen(req,timeout=180) as response: result=json.load(response)
 results.append(dict(name=name,source=str(path),seconds=time.monotonic()-start,model_file='MiniCPM-OCR-1_0-F16.gguf',response=result))
 print(name,result['choices'][0]['message']['content'],flush=True)
pathlib.Path('docs/verification/full-f16-ocr-result.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
