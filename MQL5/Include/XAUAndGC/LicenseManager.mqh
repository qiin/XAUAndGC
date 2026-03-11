//+------------------------------------------------------------------+
//|                                              LicenseManager.mqh  |
//|                         License 认证模块                          |
//|         启动验证 + 定时心跳 + 失败自动停止                          |
//+------------------------------------------------------------------+
#property copyright "Arbitrage System"
#property strict

//+------------------------------------------------------------------+
//| HTTP POST 请求                                                    |
//+------------------------------------------------------------------+
bool LicenseHttpPost(string url, string json_body, string auth_server,
                     string &response, int &http_code)
{
   char   post_data[];
   char   result_data[];
   string result_headers;
   string headers = "Content-Type: application/json\r\n";

   StringToCharArray(json_body, post_data, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(post_data, StringLen(json_body));

   ResetLastError();
   int res = WebRequest("POST", url, headers, 5000, post_data, result_data, result_headers);

   if(res == -1)
   {
      int err = GetLastError();
      if(err == 4014)
         response = "ERROR: 请在 MT5 菜单 工具→选项→EA交易 中添加允许的URL: " + auth_server;
      else
         response = "HTTP 请求失败, 错误码: " + IntegerToString(err);
      http_code = 0;
      return false;
   }

   http_code = res;
   response = CharArrayToString(result_data, 0, WHOLE_ARRAY, CP_UTF8);
   return true;
}

//+------------------------------------------------------------------+
//| 简易 JSON 解析：提取字段值                                         |
//+------------------------------------------------------------------+
string LicenseJsonGet(const string &json, const string &key)
{
   string search = "\"" + key + "\"";
   int pos = StringFind(json, search);
   if(pos < 0) return "";

   int colon = StringFind(json, ":", pos + StringLen(search));
   if(colon < 0) return "";

   int i = colon + 1;
   int len = StringLen(json);
   while(i < len && StringGetCharacter(json, i) == ' ') i++;

   if(i < len && StringGetCharacter(json, i) == '"')
   {
      int start = i + 1;
      int end = StringFind(json, "\"", start);
      if(end < 0) return "";
      return StringSubstr(json, start, end - start);
   }
   else
   {
      int start = i;
      int end = start;
      while(end < len)
      {
         ushort ch = StringGetCharacter(json, end);
         if(ch == ',' || ch == '}' || ch == ' ' || ch == '\n' || ch == '\r')
            break;
         end++;
      }
      return StringSubstr(json, start, end - start);
   }
}

//+------------------------------------------------------------------+
//| License 管理器                                                    |
//+------------------------------------------------------------------+
class CLicenseManager
{
private:
   string            m_authServer;
   string            m_licenseKey;
   string            m_instanceId;
   bool              m_authorized;
   int               m_heartbeatSec;
   int               m_failCount;       // 服务器拒绝连续次数
   int               m_netFailCount;    // 网络错误连续次数
   string            m_expireAt;
   string            m_status;
   datetime          m_lastHeartbeat;   // 上次心跳时间

   string            GenerateInstanceId();

public:
                     CLicenseManager();

   // 初始化（传入参数）
   void              Init(string authServer, string licenseKey, int heartbeatMin);

   // 启动验证（OnInit中调用，返回 false 则应阻止EA运行）
   bool              Authenticate();

   // 心跳检查（OnTimer中调用，内部按间隔自动控制频率）
   // 返回 false 表示 license 已失效，EA应停止
   bool              Heartbeat();

   // 状态查询
   bool              IsAuthorized()  { return m_authorized; }
   string            GetStatus()     { return m_status; }
   string            GetExpireAt()   { return m_expireAt; }
   int               FailCount()     { return m_failCount; }
   int               NetFailCount()  { return m_netFailCount; }
};

//+------------------------------------------------------------------+
//| 构造函数                                                          |
//+------------------------------------------------------------------+
CLicenseManager::CLicenseManager()
{
   m_authorized    = false;
   m_heartbeatSec  = 300;
   m_failCount     = 0;
   m_netFailCount  = 0;
   m_status        = "未验证";
   m_lastHeartbeat = 0;
}

//+------------------------------------------------------------------+
//| 生成唯一实例 ID                                                    |
//+------------------------------------------------------------------+
string CLicenseManager::GenerateInstanceId()
{
   string raw = TerminalInfoString(TERMINAL_DATA_PATH)
              + "|" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
              + "|" + Symbol()
              + "|" + IntegerToString(ChartID());

   ulong hash = 0;
   for(int i = 0; i < StringLen(raw); i++)
      hash = hash * 31 + StringGetCharacter(raw, i);
   return IntegerToString(hash);
}

//+------------------------------------------------------------------+
//| 初始化                                                            |
//+------------------------------------------------------------------+
void CLicenseManager::Init(string authServer, string licenseKey, int heartbeatMin)
{
   m_authServer   = authServer;
   m_licenseKey   = licenseKey;
   m_heartbeatSec = MathMax(heartbeatMin * 60, 60);
   m_instanceId   = GenerateInstanceId();

   Print("[License] 实例 ID: ", m_instanceId);
}

//+------------------------------------------------------------------+
//| 启动验证                                                          |
//+------------------------------------------------------------------+
bool CLicenseManager::Authenticate()
{
   if(m_licenseKey == "")
   {
      Print("[License] 错误: License Key 为空，请在 EA 参数中填入 License Key");
      m_status = "Key为空";
      return false;
   }

   string url = m_authServer + "/api/ea/auth";
   string body = "{\"license_key\":\"" + m_licenseKey
               + "\",\"instance_id\":\"" + m_instanceId + "\"}";

   string response;
   int http_code;

   Print("[License] 正在验证 License...");
   Print("[License] 服务器: ", m_authServer);
   Print("[License] Key: ", StringSubstr(m_licenseKey, 0, 8), "...");

   if(!LicenseHttpPost(url, body, m_authServer, response, http_code))
   {
      Print("[License] 验证失败: ", response);
      m_status = "连接失败";
      return false;
   }

   Print("[License] HTTP ", http_code, " 响应: ", response);

   if(http_code == 200)
   {
      m_status     = LicenseJsonGet(response, "status");
      m_expireAt   = LicenseJsonGet(response, "expire_at");
      string hb    = LicenseJsonGet(response, "heartbeat_seconds");
      string msg   = LicenseJsonGet(response, "message");

      if(StringLen(hb) > 0)
         m_heartbeatSec = (int)StringToInteger(hb);

      m_authorized    = true;
      m_lastHeartbeat = (datetime)TimeLocal();

      Print("[License] 验证通过! 状态: ", m_status, " 到期: ", m_expireAt,
            " 心跳: ", m_heartbeatSec, "s");
      if(StringLen(msg) > 0)
         Print("[License] 消息: ", msg);
      return true;
   }
   else
   {
      string detail = LicenseJsonGet(response, "detail");
      Print("[License] 验证被拒绝 (HTTP ", http_code, "): ", detail);
      m_status = "被拒绝";
      return false;
   }
}

//+------------------------------------------------------------------+
//| 心跳（在 OnTimer 中调用，内部控制频率）                              |
//| 返回 true=正常, false=license失效应停止EA                          |
//+------------------------------------------------------------------+
bool CLicenseManager::Heartbeat()
{
   if(!m_authorized)
      return false;

   // 按间隔控制心跳频率（避免每次 OnTimer 都发请求）
   datetime now = (datetime)TimeLocal();
   if(now - m_lastHeartbeat < m_heartbeatSec)
      return true; // 还没到时间，返回正常

   m_lastHeartbeat = now;

   string url = m_authServer + "/api/ea/heartbeat";
   string body = "{\"license_key\":\"" + m_licenseKey
               + "\",\"instance_id\":\"" + m_instanceId + "\"}";

   string response;
   int http_code;

   if(!LicenseHttpPost(url, body, m_authServer, response, http_code))
   {
      m_netFailCount++;
      m_status = "网络异常";
      Print("[License] 心跳网络错误 (连续 ", m_netFailCount, " 次): ", response);

      // 网络错误 6 次 → 失效
      if(m_netFailCount >= 6)
      {
         Print("[License] 网络连续 6 次失败，EA 停止运行");
         m_authorized = false;
         m_status = "网络断开";
         return false;
      }
      return true; // 网络暂时问题，继续运行
   }

   m_netFailCount = 0; // 网络通了

   if(http_code == 200)
   {
      m_failCount = 0;
      m_status    = LicenseJsonGet(response, "status");
      m_expireAt  = LicenseJsonGet(response, "expire_at");
      string days = LicenseJsonGet(response, "days_remaining");
      string msg  = LicenseJsonGet(response, "message");

      Print("[License] 心跳成功 | 状态: ", m_status, " | 剩余: ", days, " 天");

      if(m_status == "expired" || m_status == "disabled")
      {
         Print("[License] *** License 已失效，EA 将停止运行 ***");
         if(StringLen(msg) > 0)
            Print("[License] ", msg);
         m_authorized = false;
         return false;
      }

      if(m_status == "expiring" && StringLen(msg) > 0)
         Print("[License] 警告: ", msg);

      return true;
   }
   else if(http_code >= 1000)
   {
      // MQL5 内部错误码，视为网络错误
      m_netFailCount++;
      m_status = "连接异常(" + IntegerToString(http_code) + ")";
      Print("[License] 心跳连接异常 (代码 ", http_code, ", 连续 ", m_netFailCount, " 次)");

      if(m_netFailCount >= 6)
      {
         m_authorized = false;
         m_status = "网络断开";
         return false;
      }
      return true;
   }
   else
   {
      // 服务器明确拒绝（401/403/422等）
      m_failCount++;
      string detail = LicenseJsonGet(response, "detail");
      Print("[License] 心跳被拒绝 (HTTP ", http_code, ", 连续 ", m_failCount, " 次): ", detail);

      // 服务器拒绝 3 次 → 失效
      if(m_failCount >= 3)
      {
         Print("[License] 服务器连续 3 次拒绝，License 已失效，EA 停止运行");
         m_authorized = false;
         m_status = "已失效";
         return false;
      }
      return true;
   }
}
