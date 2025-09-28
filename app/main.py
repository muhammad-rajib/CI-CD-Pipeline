from fastapi import FastAPI


app = FastAPI()

# app
@app.get("/")
async def root():
    return {"message": "Hello from FastAPI (Docker)"}


@app.get("/health")
async def health():
    return {"status": "ok"}
