
// Base64 string for a simple 1x1 transparent pixel GIF (valid image)
const MOCK_QR_BASE64 = "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7";

export const getMockQrResponse = () => {
  return {
    qr_image_base64: MOCK_QR_BASE64,
    redirect_url: "https://www.lbp-eservices.com/egps/portal/Merchants.jsp",
    transaction_id: "TXN-MOCK-" + new Date().getTime(),
  };
};
