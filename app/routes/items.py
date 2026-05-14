from fastapi import APIRouter, HTTPException

from app.models import Item, ItemCreate

router = APIRouter()

_items: list[Item] = [
    Item(id=1, name="Widget", description="A standard widget", price=9.99),
    Item(id=2, name="Gadget", description="An advanced gadget", price=29.99),
]
_counter = 3


@router.get("/", response_model=list[Item])
async def list_items():
    return _items


@router.get("/{item_id}", response_model=Item)
async def get_item(item_id: int):
    for item in _items:
        if item.id == item_id:
            return item
    raise HTTPException(status_code=404, detail=f"Item {item_id} not found")


@router.post("/", response_model=Item, status_code=201)
async def create_item(payload: ItemCreate):
    global _counter
    new_item = Item(id=_counter, **payload.model_dump())
    _counter += 1
    _items.append(new_item)
    return new_item


@router.delete("/{item_id}", status_code=204)
async def delete_item(item_id: int):
    global _items
    original_len = len(_items)
    _items = [i for i in _items if i.id != item_id]
    if len(_items) == original_len:
        raise HTTPException(status_code=404, detail=f"Item {item_id} not found")
