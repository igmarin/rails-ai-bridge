ActiveRecord::Schema[8.0].define(version: 2026_04_30_160000) do
  create_table "patient_records", force: :cascade do |t|
    t.string "external_reference", null: false
    t.string "ssn_digest", null: false
    t.text "encrypted_notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_reference"], name: "index_patient_records_on_external_reference", unique: true
  end
end
