import base64,json,pathlib,time,urllib.request
root=pathlib.Path('docs/verification')
def b64(name): return 'data:image/png;base64,'+base64.b64encode((root/name).read_bytes()).decode()
def post(port,path,body):
 r=urllib.request.Request(f'http://127.0.0.1:{port}/{path}',data=json.dumps(body).encode(),headers={'Content-Type':'application/json'})
 with urllib.request.urlopen(r,timeout=180) as response:return json.load(response)
results={}
results['word_ocr']=post(18499,'v1/chat/completions',dict(model='minicpm-ocr',stream=False,messages=[dict(role='user',content=[dict(type='image_url',image_url=dict(url=b64('word-original.png'))),dict(type='text',text='Text Recognition:')])],max_tokens=128,temperature=.01,top_p=.001,top_k=1,repeat_penalty=1))
print('WORD OCR',results['word_ocr']['choices'][0]['message'],flush=True)
for word in ['beautiful','beautifull']:
 results[word]=post(18500,'v1/systemone',dict(state=word,files=[b64('word-original.png'),b64(f'word-render-{word}.png')],questions=dict(consistency=dict(type='choice',criteria={'0':None,'1':None}))))
 print('JEV',word,results[word],flush=True)
(root/'word-candidate-probe.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
