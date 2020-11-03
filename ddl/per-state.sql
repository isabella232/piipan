BEGIN;

CREATE TABLE uploads(
	id serial PRIMARY KEY,
	created_at timestamp NOT NULL,
	publisher text NOT NULL
);

COMMENT ON TABLE uploads IS 'Bulk PII upload events';
COMMENT ON COLUMN uploads.created_at IS 'Date/time the records were uploaded in bulk';
COMMENT ON COLUMN uploads.publisher IS 'User or service account that performed the upload';
	
CREATE TABLE participants(
	id serial PRIMARY KEY,
	last text NOT NULL,
	first text,
	middle text,
	dob date NOT NULL,
	ssn text NOT NULL,
	exception text,
	upload_id integer REFERENCES uploads (id)
);

COMMENT ON TABLE participants IS 'Program participant Personally Identifiable Information (PII)';
COMMENT ON COLUMN participants.last IS 'Participant''s last name';
COMMENT ON COLUMN participants.first IS 'Participant''s first name';
COMMENT ON COLUMN participants.middle IS 'Participant''s middle name';
COMMENT ON COLUMN participants.dob IS 'Participant''s date of birth';
COMMENT ON COLUMN participants.ssn IS 'Participant''s Social Security Number';
COMMENT ON COLUMN participants.exception IS 'Placeholder for value indicating special processing instructions';

CREATE INDEX participants_ssn_idx ON participants (ssn, upload_id);

COMMIT;
