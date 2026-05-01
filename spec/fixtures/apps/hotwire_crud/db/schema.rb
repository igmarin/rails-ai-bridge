ActiveRecord::Schema[8.0].define(version: 2026_04_30_130000) do
  create_table "conversations", force: :cascade do |t|
    t.string "title", null: false
    t.string "status", null: false, default: "open"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "messages", force: :cascade do |t|
    t.integer "conversation_id", null: false
    t.string "author_name", null: false
    t.text "body", null: false
    t.datetime "edited_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
  end
end
