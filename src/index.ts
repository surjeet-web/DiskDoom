import type { Env } from "./types";
import { errorResponse, jsonResponse } from "./responses";
import { handleValidate } from "./license";
import { handleActivate, handleDeactivate } from "./activation";
import { handleAdminStats, handleListActivations, handleRevoke } from "./admin";
import { LicenseDO } from "./license-do";

export { LicenseDO };

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    if (method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin":
            request.headers.get("Origin") &&
            env.ALLOWED_ORIGINS.split(",").map(x => x.trim()).includes(
              request.headers.get("Origin")!
            )
              ? request.headers.get("Origin")!
              : "",
          "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization",
          "Access-Control-Max-Age": "86400"
        }
      });
    }

    try {
      if (path === "/v1/health" && method === "GET") {
        return jsonResponse(request, env, {
          status: "ok",
          environment: env.ENVIRONMENT,
          timestamp: new Date().toISOString()
        });
      }

      if (path === "/v1/validate" && method === "POST") {
        return await handleValidate(request, env);
      }

      if (path === "/v1/activate" && method === "POST") {
        return await handleActivate(request, env);
      }

      if (path === "/v1/deactivate" && method === "POST") {
        return await handleDeactivate(request, env);
      }

      if (path === "/v1/admin/revoke" && method === "POST") {
        return await handleRevoke(request, env);
      }

      if (path === "/v1/admin/activations" && method === "GET") {
        return await handleListActivations(request, url, env);
      }

      if (path === "/v1/admin/stats" && method === "GET") {
        return await handleAdminStats(request, env);
      }

      return errorResponse(request, env, "not_found", "Endpoint not found.", 404);
    } catch (error) {
      console.error("Unhandled worker error:", error);
      return errorResponse(request, env, "internal_error", "Internal server error.", 500);
    }
  }
};
