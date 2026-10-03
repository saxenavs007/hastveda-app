-- One invoice row and one Resend send per Cashfree order.
-- A retry can claim an unsent row. A live claim blocks the other endpoint.

CREATE TABLE IF NOT EXISTS public.payment_invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cashfree_order_id text NOT NULL,
  cashfree_order_uuid uuid,
  invoice_number text NOT NULL,
  user_id uuid NOT NULL,
  customer_name text,
  customer_email text,
  description text,
  sac_code text,
  base_amount numeric NOT NULL DEFAULT 0,
  gst_rate numeric NOT NULL DEFAULT 0.18,
  gst_amount numeric NOT NULL DEFAULT 0,
  total_amount numeric NOT NULL DEFAULT 0,
  currency text NOT NULL DEFAULT 'INR',
  payment_reference text,
  status text NOT NULL DEFAULT 'generated',
  resend_email_id text,
  sent_at timestamptz,
  send_claimed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.payment_invoices
  ADD COLUMN IF NOT EXISTS send_claimed_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS payment_invoices_cashfree_order_id_key
  ON public.payment_invoices (cashfree_order_id);

ALTER TABLE public.payment_invoices ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON public.payment_invoices TO service_role;

CREATE OR REPLACE FUNCTION public.claim_invoice_send(p_invoice_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated integer;
BEGIN
  UPDATE public.payment_invoices
  SET status = 'sending',
      send_claimed_at = now()
  WHERE id = p_invoice_id
    AND resend_email_id IS NULL
    AND (
      status IS DISTINCT FROM 'sending'
      OR send_claimed_at IS NULL
      OR send_claimed_at < now() - interval '2 minutes'
    );

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_invoice_send(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_invoice_send(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.claim_invoice_send(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.claim_invoice_send(uuid) TO service_role;
