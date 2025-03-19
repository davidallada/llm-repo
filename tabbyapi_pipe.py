from typing import Union, Generator, Iterator, List
from pydantic import BaseModel

import os
import requests



# Pipe Class: This class functions as a customizable pipeline.
# It can be adapted to work with any external or internal models,
# making it versatile for various use cases outside of just OpenAI models.
class Pipeline:
    class Valves(BaseModel):
        TABBY_API_BASE_URL: str = "http://10.69.1.169:5000/v1"
        TABBY_API_KEY: str = os.environ["TABBY_API_KEY"]

    def __init__(self):
        self.type = "manifold"
        self.valves = self.Valves()
        self.pipelines = self.get_tabby_models()

    def get_tabby_models(self):
        if self.valves.TABBY_API_KEY:
            try:
                headers = {}
                headers["Authorization"] = f"Bearer {self.valves.TABBY_API_KEY}"
                headers["x-api-key"] = f"{self.valves.TABBY_API_KEY}"
                headers["x-admin-key"] = f"{self.valves.TABBY_API_KEY}"
                headers["Content-Type"] = "application/json"

                r = requests.get(
                    f"{self.valves.TABBY_API_BASE_URL}/model/list", headers=headers
                )

                models = r.json()
                return [
                    {
                        "id": model["id"],
                        "name": model["name"] if "name" in model else model["id"],
                    }
                    for model in models["data"]
                ]

            except Exception as e:

                print(f"Error: {e}")
                return [
                    {
                        "id": "error",
                        "name": "Could not fetch models from TabbyAPI, please update the API Key in the valves.",
                    },
                ]
        else:
            return []

    def pipe(
        self, user_message: str, model_id: str, messages: List[dict], body: dict
    ) -> Union[str, Generator, Iterator]:

        headers = {}
        headers["Authorization"] = f"Bearer {self.valves.TABBY_API_KEY}"
        headers["x-api-key"] = f"{self.valves.TABBY_API_KEY}"
        headers["x-admin-key"] = f"{self.valves.TABBY_API_KEY}"
        headers["Content-Type"] = "application/json"

        # payload = {**body, "model": model_id}
        payload = {
            **body
        }
        payload["draft_model"] = {
            "draft_model_name": "Qwen_Qwen2.5-Coder-0.5B-Instruct-4.0-bpw"
        }
        print(payload)
        try:
            r = requests.post(
                url=f"{self.valves.TABBY_API_BASE_URL}/chat/completions",
                json=payload,
                headers=headers,
                stream=True,
            )

            r.raise_for_status()

            if body["stream"]:
                return r.iter_lines()
            else:
                return r.json()
        except Exception as e:
            return f"Error: {e}"