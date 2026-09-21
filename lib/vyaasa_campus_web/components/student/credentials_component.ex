defmodule VyaasaCampusWeb.Components.Student.CredentialsComponent do
  @moduledoc """
  "Credentials" section on the student profile page — the View Employability
  Card / View Certificate tabs, the flippable AI8 employability card, and the
  VYAASA Gold Level certificate.

  Presentation only: `active_tab` and `card_flipped` are owned by the parent
  LiveView (see `VyaasaCampusWeb.Student.ProfileLive`), and the `toggle_tab` /
  `rotate_card` events emitted here bubble up to it.
  """
  use Phoenix.Component

  import VyaasaCampusWeb.Components.UI, only: [icon: 1]

  attr :active_tab, :string, default: "none", values: ~w(none card certificate)
  attr :card_flipped, :boolean, default: false
  attr :student_name, :string, required: true
  attr :role, :string, required: true
  attr :initials, :string, required: true
  attr :cert_id, :string, required: true
  attr :issued_on, :string, required: true
  attr :valid_until, :string, required: true
  attr :score, :integer, required: true
  attr :tier, :map, required: true
  attr :qr_url, :string, required: true

  def credentials(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-200 shadow-card-soft p-6">
      <div class="flex items-center justify-between flex-wrap gap-3">
        <h2 class="text-base font-bold text-gray-900">Credentials</h2>

        <div class="flex items-center gap-2">
          <button type="button" phx-click="toggle_tab" phx-value-tab="card" class={tab_class(@active_tab == "card")}>
            <.icon name="hero-credit-card" class="w-4 h-4" /> View Vyaasa Card
          </button>
          <button type="button" phx-click="toggle_tab" phx-value-tab="certificate" class={tab_class(@active_tab == "certificate")}>
            <.icon name="hero-document-check" class="w-4 h-4" /> View Vyaasa Certificate
          </button>
        </div>
      </div>

      <div :if={@active_tab == "card"} class="mt-6 flex justify-center">
        <.employability_card
          flipped={@card_flipped}
          student_name={@student_name}
          role={@role}
          initials={@initials}
          cert_id={@cert_id}
          score={@score}
          tier={@tier}
          qr_url={@qr_url}
        />
      </div>

      <div :if={@active_tab == "certificate"} class="mt-6">
        <.certificate
          student_name={@student_name}
          cert_id={@cert_id}
          issued_on={@issued_on}
          valid_until={@valid_until}
          score={@score}
          qr_url={@qr_url}
        />
      </div>
    </div>
    """
  end

  attr :flipped, :boolean, required: true
  attr :student_name, :string, required: true
  attr :role, :string, required: true
  attr :initials, :string, required: true
  attr :cert_id, :string, required: true
  attr :score, :integer, required: true
  attr :tier, :map, required: true
  attr :qr_url, :string, required: true

  defp employability_card(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-4 w-full max-w-sm">
      <div class="perspective-distant w-full">
        <div
          phx-click="rotate_card"
          class={[
            "relative w-full aspect-568/369 cursor-pointer transform-3d transition-transform duration-700 ease-in-out",
            @flipped && "transform-[rotateY(180deg)]"
          ]}
        >
          <!-- Front -->
          <div class="absolute inset-0 backface-hidden rounded-2xl overflow-hidden bg-[#FCFBF9] border border-gray-100 shadow-lg flex items-center justify-center">
            <!-- bottom-left wave: dark base, light layered on top -->
            <svg class="absolute bottom-0 left-0 w-[33.3%] h-auto" viewBox="0 0 121 106" fill="none" aria-hidden="true">
              <path
                d="M14.6344 44.0494C13.4571 41.8561 -6.03801 1.54482 -6.62784 0.916476L-13.0173 0.000153188L-29.5663 104.969L110.247 125.835C115.985 126.568 129.362 126.023 110.712 110.276C92.0624 94.5295 83.3855 85.1868 56.2736 74.8863C29.1617 64.5857 15.8117 46.2427 14.6344 44.0494Z"
                fill="#FEA337"
              />
            </svg>
            <svg class="absolute bottom-0 left-0 w-[25.2%] h-auto" viewBox="0 0 143 99" fill="none" aria-hidden="true">
              <path
                d="M26.7465 39.6777C25.2698 37.6738 0.249603 0.538252 -0.423456 0H-6.87829L-8.3584 106.255L133.001 107.062C138.785 106.973 151.949 104.535 131.253 91.5948C110.557 78.6549 100.641 70.6387 72.3416 64.2913C44.042 57.9438 28.2233 41.6817 26.7465 39.6777Z"
                fill="#EF6C00"
              />
            </svg>

            <!-- top-right wave: dark base, light layered on top -->
            <svg class="absolute top-0 right-0 w-[35.6%] h-auto" viewBox="0 0 134 91" fill="none" aria-hidden="true">
              <path
                d="M113.638 49.6099C115.049 51.6604 138.858 89.5838 139.514 90.1434L145.965 90.3517L150.872 -15.8006L9.61218 -21.1673C3.82879 -21.2643 -9.40707 -19.2522 10.8608 -5.65149C31.1287 7.94925 40.7802 16.2812 68.8603 23.5383C96.9405 30.7953 112.226 47.5593 113.638 49.6099Z"
                fill="#FEA337"
              />
            </svg>
            <svg class="absolute top-0 right-0 w-[27.1%] h-auto" viewBox="0 0 154 85" fill="none" aria-hidden="true">
              <path
                d="M121.976 48.328C123.664 50.1574 152.615 84.3168 153.344 84.7777L159.759 84.068L149.547 -21.7058L8.95629 -6.96509C3.21771 -6.24007 -9.59848 -2.36942 12.3949 8.21638C34.3882 18.8022 45.1248 25.6796 73.9508 28.877C102.777 32.0743 120.288 46.4985 121.976 48.328Z"
                fill="#EF6C00"
              />
            </svg>

            <img src="/images/logo.png" class="w-2/5 max-w-52 relative z-10" alt="VYAASA" />
          </div>

          <!-- Back -->
          <div class="absolute inset-0 backface-hidden transform-[rotateY(180deg)] rounded-2xl overflow-hidden bg-[#FEFBF7] border border-gray-100 shadow-lg p-4 sm:p-5 flex flex-col">
            <!-- faint diagonal watermark -->
            <div class="pointer-events-none absolute inset-0 overflow-hidden select-none" aria-hidden="true">
              <span class="absolute top-0 left-6 text-3xl font-black text-[#EF6C0008] -rotate-18 whitespace-nowrap">VYAASA VYAASA</span>
              <span class="absolute top-1/3 -left-10 text-3xl font-black text-[#EF6C0008] -rotate-18 whitespace-nowrap">VYAASA VYAASA</span>
              <span class="absolute bottom-0 left-10 text-3xl font-black text-[#EF6C0008] -rotate-18 whitespace-nowrap">VYAASA VYAASA</span>
            </div>

            <!-- bottom-left wave: dark base, light layered on top -->
            <svg class="absolute bottom-0 left-0 w-[33.3%] h-auto" viewBox="0 0 121 106" fill="none" aria-hidden="true">
              <path
                d="M14.6344 44.0494C13.4571 41.8561 -6.03801 1.54482 -6.62784 0.916476L-13.0173 0.000153188L-29.5663 104.969L110.247 125.835C115.985 126.568 129.362 126.023 110.712 110.276C92.0624 94.5295 83.3855 85.1868 56.2736 74.8863C29.1617 64.5857 15.8117 46.2427 14.6344 44.0494Z"
                fill="#FEA337"
              />
            </svg>
            <svg class="absolute bottom-0 left-0 w-[25.2%] h-auto" viewBox="0 0 143 99" fill="none" aria-hidden="true">
              <path
                d="M26.7465 39.6777C25.2698 37.6738 0.249603 0.538252 -0.423456 0H-6.87829L-8.3584 106.255L133.001 107.062C138.785 106.973 151.949 104.535 131.253 91.5948C110.557 78.6549 100.641 70.6387 72.3416 64.2913C44.042 57.9438 28.2233 41.6817 26.7465 39.6777Z"
                fill="#EF6C00"
              />
            </svg>

            <div class="relative z-10 flex items-center justify-between">
              <img src="/images/logo.png" class="h-14 w-auto" alt="VYAASA" />
              <span class="inline-flex items-center gap-1 text-[10px] font-bold px-2.5 py-1 rounded-sm border border-orange-300 text-orange-600 bg-white">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 24 24"
                  class="w-4 h-4"
                >
                  <path
                    d="M12 2.5L19 5.5V10.7C19 15.2 16.3 19.1 12 21.5C7.7 19.1 5 15.2 5 10.7V5.5L12 2.5Z"
                    fill="#EF6C00"
                  />
                  <path
                    d="M9.2 12.1L11.2 14.1L15.3 10"
                    stroke="white"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg> VYAASA VERIFIED
              </span>
            </div>

            <div class="relative z-10 mt-2 flex items-center gap-2 flex-1 min-h-0 mb-3.25">
              <div class="flex flex-col items-center shrink-0">
                <div class="flex items-center justify-center gap-1">
                  <.score_dots />

                  <p class="text-[44px] font-bold leading-none text-[#F97316]">
                    {@score}
                  </p>

                  <.score_dots flip />
                </div>

                <!-- AI8 Score -->
                <div class="mt-1 flex items-center justify-center gap-1">
                  <div class="w-4 h-[0.94px] rounded-full bg-[#EF6C00]/70"></div>

                  <span class="text-[8.8px] font-normal uppercase tracking-[0.22em] text-[#3F4756] leading-none whitespace-nowrap">
                    AI8 SCORE
                  </span>

                  <div class="w-4 h-[0.94px] rounded-full bg-[#EF6C00]/70"></div>
                </div>

              </div>

              <div class="w-px h-18 bg-[#EF6C004D]"></div>

              <div class="flex-1 grid grid-cols-1 gap-1 min-w-0 pl-1">
                <.metric_row icon="hero-trophy" title={@tier.percentile} subtitle="Among All Candidates" />
                <.metric_row icon="trending-up" title={@tier.potential} subtitle="Employability Tier" />
                <.metric_row icon="check-badge" title={@tier.readiness} subtitle="Career Ready Candidate" />
              </div>

              <div class="w-px h-18 bg-[#EF6C004D]"></div>

              <div class="shrink-0 flex flex-col items-center">
                <div class="relative p-1 bg-white border border-dashed border-orange-200 rounded-lg shadow-xs">
                  <img src={@qr_url} class="w-14 h-14 rounded" alt="Scan to view profile" />
                  <img
                    src="/images/vyaasa-mark.svg"
                    class="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-4 h-4 rounded-full bg-white p-0.5"
                    alt=""
                    aria-hidden="true"
                  />
                </div>
                <p class="mt-1 text-[7px] font-medium text-orange-500 text-center leading-tight">SCAN TO VIEW<br />PROFILE</p>
              </div>
            </div>

            <div class="relative z-10 mt-2 pt-2.5 border-t border-[#EF6C00] grid grid-cols-[1fr_auto_1fr] items-center gap-3 shrink-0">
              <div></div>
              <div class="flex flex-col items-center">
                <div class="flex items-center gap-2">
                  <.laurel />
                  <div class="text-center">
                    <p class="text-xs font-bold text-[#111827] uppercase line-clamp-2 wrap-break-word leading-tight max-w-32">{@student_name}</p>
                    <div class="flex items-center justify-center gap-1">
                      <div class="w-10.5 h-[0.94px] rounded-full bg-[#EF6C00]/70"></div>
                          <p class="text-[8.8px] font-normal text-[#374151] uppercase">{@role}</p>
                      <div class="w-10.5 h-[0.94px] rounded-full bg-[#EF6C00]/70"></div>
                    </div>
                  </div>
                  <.laurel flip />
                </div>
                <span class="mt-1 inline-flex items-center gap-1 text-[9px] font-semibold text-gray-500 border border-gray-200 rounded-full px-2 py-0.5">
                  <.icon name="hero-identification" class="w-3 h-3 text-orange-400" /> {@cert_id}
                </span>
              </div>
              <div class="flex justify-end">
                <.ai8_seal />
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="flex items-center gap-3">
        <button
          type="button"
          phx-click="rotate_card"
          class="inline-flex items-center gap-2 text-sm font-semibold px-4 py-2 rounded-lg border border-gray-200 text-gray-700 hover:bg-gray-50 transition"
        >
          <.icon name="hero-arrow-path" class="w-4 h-4" /> Rotate Card
        </button>

        <button
          type="button"
          phx-click="email_employability_card"
          title="Your employability card is emailed to you as a PDF. Click to send/resend."
          class="inline-flex items-center gap-2 text-sm font-semibold px-4 py-2.5 rounded-lg text-white transition"
          style="background-color: #FF8B00;"
        >
          <.icon name="hero-envelope" class="w-4 h-4" /> Email Card
        </button>
      </div>
    </div>
    """
  end

  attr :flip, :boolean, default: false

  defp score_dots(assigns) do
    ~H"""
    <div class={["relative w-[19.8px] h-9.25 shrink-0", @flip && "rotate-180"]}>
      <svg class="absolute right-0 top-1/2 -translate-y-1/2 w-[19.8px] h-auto" viewBox="0 0 38 84" fill="none" aria-hidden="true">
        <path d="M29.4804 4.83176C29.9956 6.922 32.1078 8.19883 34.198 7.68363C36.2883 7.16843 37.5651 5.0563 37.0499 2.96606C36.5347 0.875809 34.4225 -0.401019 32.3323 0.114181C30.2421 0.62938 28.9652 2.74151 29.4804 4.83176Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M21.0273 9.04263C22.0277 10.9488 24.3841 11.6831 26.2903 10.6826C28.1965 9.68218 28.9307 7.32586 27.9303 5.41965C26.9298 3.51344 24.5735 2.77918 22.6673 3.77964C20.7611 4.78009 20.0268 7.13641 21.0273 9.04263Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M13.8275 15.1541C15.2551 16.7655 17.7186 16.9145 19.33 15.4869C20.9414 14.0594 21.0904 11.5958 19.6629 9.98441C18.2353 8.37301 15.7717 8.22399 14.1603 9.65157C12.5489 11.0791 12.3999 13.5427 13.8275 15.1541Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M8.29949 22.811C10.0712 24.034 12.4989 23.5891 13.7218 21.8173C14.9447 20.0456 14.4998 17.618 12.7281 16.395C10.9564 15.1721 8.52875 15.617 7.30581 17.3887C6.08288 19.1604 6.52777 21.5881 8.29949 22.811Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M4.76454 31.5684C6.77744 32.3318 9.02808 31.3188 9.79147 29.3059C10.5549 27.293 9.54194 25.0424 7.52903 24.279C5.51613 23.5156 3.2655 24.5285 2.5021 26.5414C1.7387 28.5543 2.75163 30.805 4.76454 31.5684Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M3.42808 40.9172C5.56518 41.1767 7.50801 39.6546 7.7675 37.5175C8.02699 35.3804 6.50489 33.4376 4.36778 33.1781C2.23067 32.9186 0.287849 34.4407 0.0283585 36.5778C-0.231133 38.7149 1.29097 40.6577 3.42808 40.9172Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M4.36778 50.3143C6.50489 50.0548 8.02699 48.1119 7.7675 45.9748C7.50801 43.8377 5.56518 42.3156 3.42808 42.5751C1.29097 42.8346 -0.231133 44.7774 0.0283585 46.9145C0.287849 49.0516 2.23067 50.5737 4.36778 50.3143Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M7.52903 59.2133C9.54194 58.4499 10.5549 56.1993 9.79147 54.1864C9.02808 52.1735 6.77744 51.1606 4.76453 51.924C2.75163 52.6874 1.7387 54.938 2.50209 56.9509C3.26549 58.9638 5.51613 59.9767 7.52903 59.2133Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M12.7281 67.0973C14.4998 65.8744 14.9447 63.4467 13.7218 61.675C12.4989 59.9033 10.0712 59.4584 8.29949 60.6813C6.52776 61.9042 6.08288 64.3319 7.30581 66.1036C8.52875 67.8753 10.9564 68.3202 12.7281 67.0973Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M19.6629 73.5079C21.0904 71.8965 20.9414 69.433 19.33 68.0054C17.7186 66.5778 15.2551 66.7268 13.8275 68.3382C12.3999 69.9496 12.5489 72.4132 14.1603 73.8408C15.7717 75.2683 18.2353 75.1193 19.6629 73.5079Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M27.9303 78.0727C28.9307 76.1665 28.1965 73.8102 26.2903 72.8097C24.3841 71.8092 22.0277 72.5435 21.0273 74.4497C20.0268 76.3559 20.7611 78.7122 22.6673 79.7127C24.5735 80.7132 26.9298 79.9789 27.9303 78.0727Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M37.0499 80.5263C37.5651 78.436 36.2883 76.3239 34.198 75.8087C32.1078 75.2935 29.9956 76.5703 29.4804 78.6606C28.9652 80.7508 30.2421 82.863 32.3323 83.3782C34.4225 83.8934 36.5347 82.6165 37.0499 80.5263Z" fill="#EF6C00" fill-opacity="0.2" />
      </svg>

      <svg class="absolute right-0 top-1/2 -translate-y-1/2 w-[15.6px] h-auto" viewBox="0 0 30 67" fill="none" aria-hidden="true">
        <path d="M23.3931 3.83408C23.802 5.49272 25.478 6.50591 27.1366 6.09709C28.7953 5.68827 29.8084 4.01226 29.3996 2.35361C28.9908 0.694969 27.3148 -0.318215 25.6562 0.0906043C23.9975 0.499424 22.9843 2.17543 23.3931 3.83408Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M16.6854 7.17547C17.4793 8.68808 19.3491 9.27073 20.8617 8.47685C22.3743 7.68297 22.957 5.81319 22.1631 4.30058C21.3692 2.78797 19.4994 2.20532 17.9868 2.9992C16.4742 3.79308 15.8916 5.66286 16.6854 7.17547Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M10.9723 12.025C12.1051 13.3037 14.06 13.4219 15.3386 12.2891C16.6173 11.1563 16.7356 9.20146 15.6028 7.92279C14.47 6.64412 12.5151 6.52587 11.2364 7.65868C9.95773 8.79148 9.83948 10.7464 10.9723 12.025Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M6.58572 18.1009C7.99161 19.0713 9.91799 18.7183 10.8884 17.3124C11.8588 15.9065 11.5058 13.9802 10.0999 13.0097C8.69402 12.0393 6.76764 12.3923 5.79722 13.7982C4.82681 15.2041 5.17983 17.1305 6.58572 18.1009Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M3.78068 25.05C5.37795 25.6558 7.16387 24.852 7.76963 23.2547C8.3754 21.6575 7.57162 19.8715 5.97435 19.2658C4.37708 18.66 2.59116 19.4638 1.9854 21.0611C1.37963 22.6583 2.18341 24.4443 3.78068 25.05Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M2.72017 32.4685C4.416 32.6744 5.95767 31.4666 6.16358 29.7708C6.36949 28.0749 5.16167 26.5333 3.46585 26.3273C1.77002 26.1214 0.228352 27.3293 0.0224419 29.0251C-0.18347 30.7209 1.02435 32.2626 2.72017 32.4685Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M3.46585 39.9252C5.16167 39.7193 6.36949 38.1776 6.16358 36.4818C5.95767 34.7859 4.416 33.5781 2.72017 33.784C1.02435 33.99 -0.18347 35.5316 0.0224419 37.2274C0.228352 38.9233 1.77002 40.1311 3.46585 39.9252Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M5.97435 46.9867C7.57162 46.381 8.3754 44.5951 7.76963 42.9978C7.16387 41.4005 5.37795 40.5967 3.78068 41.2025C2.1834 41.8083 1.37963 43.5942 1.98539 45.1915C2.59116 46.7887 4.37708 47.5925 5.97435 46.9867Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M10.0999 53.2428C11.5058 52.2724 11.8588 50.346 10.8884 48.9401C9.91798 47.5342 7.99161 47.1812 6.58572 48.1516C5.17983 49.122 4.82681 51.0484 5.79722 52.4543C6.76764 53.8602 8.69401 54.2132 10.0999 53.2428Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M15.6028 58.3297C16.7356 57.0511 16.6173 55.0962 15.3386 53.9634C14.06 52.8306 12.1051 52.9488 10.9723 54.2275C9.83948 55.5062 9.95773 57.4611 11.2364 58.5939C12.5151 59.7267 14.47 59.6084 15.6028 58.3297Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M22.1631 61.9519C22.957 60.4393 22.3743 58.5696 20.8617 57.7757C19.3491 56.9818 17.4793 57.5644 16.6854 59.0771C15.8915 60.5897 16.4742 62.4594 17.9868 63.2533C19.4994 64.0472 21.3692 63.4646 22.1631 61.9519Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M29.3996 63.8989C29.8084 62.2403 28.7953 60.5643 27.1366 60.1554C25.478 59.7466 23.802 60.7598 23.3931 62.4184C22.9843 64.0771 23.9975 65.7531 25.6562 66.1619C27.3148 66.5707 28.9908 65.5576 29.3996 63.8989Z" fill="#EF6C00" fill-opacity="0.2" />
      </svg>

      <svg class="absolute right-0 top-1/2 -translate-y-1/2 w-[14.3px] h-auto" viewBox="0 0 22 50" fill="none" aria-hidden="true">
        <path d="M17.3501 2.84361C17.6533 4.07377 18.8963 4.82522 20.1265 4.52201C21.3566 4.2188 22.1081 2.97576 21.8049 1.7456C21.5017 0.515435 20.2586 -0.236009 19.0285 0.0671982C17.7983 0.370406 17.0469 1.61345 17.3501 2.84361Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M12.3752 5.32181C12.964 6.44366 14.3507 6.87579 15.4726 6.287C16.5944 5.6982 17.0266 4.31145 16.4378 3.1896C15.849 2.06774 14.4622 1.63561 13.3404 2.22441C12.2185 2.8132 11.7864 4.19996 12.3752 5.32181Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M8.13792 8.91857C8.97808 9.86691 10.428 9.95461 11.3763 9.11445C12.3246 8.27429 12.4123 6.82442 11.5722 5.87607C10.732 4.92773 9.28215 4.84002 8.33381 5.68019C7.38546 6.52035 7.29776 7.97022 8.13792 8.91857Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M4.88455 13.4248C5.92725 14.1446 7.35599 13.8828 8.07571 12.84C8.79544 11.7973 8.53361 10.3686 7.49091 9.64889C6.44821 8.92916 5.01948 9.19099 4.29975 10.2337C3.58002 11.2764 3.84185 12.7051 4.88455 13.4248Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M2.80415 18.5788C3.98879 19.028 5.31335 18.4319 5.76262 17.2473C6.2119 16.0626 5.61576 14.7381 4.43112 14.2888C3.24648 13.8395 1.92192 14.4356 1.47265 15.6203C1.02337 16.8049 1.6195 18.1295 2.80415 18.5788Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M2.01761 24.0808C3.27535 24.2335 4.41875 23.3377 4.57146 22.08C4.72418 20.8222 3.82839 19.6788 2.57064 19.5261C1.3129 19.3734 0.169504 20.2692 0.0167866 21.5269C-0.135929 22.7847 0.759867 23.9281 2.01761 24.0808Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M2.57064 29.6112C3.82839 29.4585 4.72418 28.3151 4.57146 27.0573C4.41875 25.7996 3.27535 24.9038 2.01761 25.0565C0.759867 25.2092 -0.135929 26.3526 0.0167866 27.6104C0.169504 28.8681 1.3129 29.7639 2.57064 29.6112Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M4.43112 34.8485C5.61576 34.3992 6.2119 33.0747 5.76262 31.89C5.31335 30.7054 3.98879 30.1093 2.80414 30.5585C1.6195 31.0078 1.02337 32.3324 1.47264 33.517C1.92192 34.7017 3.24648 35.2978 4.43112 34.8485Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M7.49091 39.4884C8.53361 38.7687 8.79543 37.34 8.07571 36.2973C7.35598 35.2546 5.92725 34.9927 4.88455 35.7125C3.84185 36.4322 3.58002 37.8609 4.29975 38.9036C5.01948 39.9463 6.4482 40.2081 7.49091 39.4884Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M11.5722 43.2612C12.4123 42.3129 12.3246 40.863 11.3763 40.0229C10.428 39.1827 8.97808 39.2704 8.13792 40.2187C7.29776 41.1671 7.38546 42.617 8.33381 43.4571C9.28215 44.2973 10.732 44.2096 11.5722 43.2612Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M16.4378 45.9477C17.0266 44.8259 16.5944 43.4391 15.4726 42.8503C14.3507 42.2615 12.964 42.6936 12.3752 43.8155C11.7864 44.9373 12.2185 46.3241 13.3404 46.9129C14.4622 47.5017 15.849 47.0696 16.4378 45.9477Z" fill="#EF6C00" fill-opacity="0.2" />
        <path d="M21.8049 47.3917C22.1081 46.1615 21.3566 44.9185 20.1265 44.6153C18.8963 44.3121 17.6533 45.0635 17.3501 46.2937C17.0469 47.5239 17.7983 48.7669 19.0285 49.0701C20.2586 49.3733 21.5017 48.6219 21.8049 47.3917Z" fill="#EF6C00" fill-opacity="0.2" />
      </svg>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, required: true

  defp metric_row(assigns) do
    ~H"""
    <div class="flex items-center gap-1.5 min-w-0">
      <div class="w-6 h-6 rounded-md bg-orange-50 flex items-center justify-center shrink-0">
        <.trending_up_icon :if={@icon == "trending-up"} />
        <.check_badge_icon :if={@icon == "check-badge"} />
        <.icon :if={@icon not in ["trending-up", "check-badge"]} name={@icon} class="w-3.5 h-3.5 text-orange-400" />
      </div>
      <div class="min-w-0 leading-tight">
        <p class="text-[10.07px] font-bold text-[#1F2937] truncate uppercase">{@title}</p>
        <p class="text-[7.56px] font-normal text-[#6B7280] truncate">{@subtitle}</p>
      </div>
    </div>
    """
  end

  defp trending_up_icon(assigns) do
    ~H"""
    <svg class="w-3.5 h-3.5" viewBox="0 0 13 13" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
      <g clip-path="url(#credentials-trending-up-clip)">
        <path d="M6.2959 8.39453V11.018" stroke="#EF6C00" stroke-width="1.04938" stroke-linecap="round" stroke-linejoin="round" />
        <path d="M8.39453 7.68164V11.0192" stroke="#EF6C00" stroke-width="1.04938" stroke-linecap="round" stroke-linejoin="round" />
        <path d="M10.4932 5.59082V11.0182" stroke="#EF6C00" stroke-width="1.04938" stroke-linecap="round" stroke-linejoin="round" />
        <path
          d="M11.5427 1.57324L7.00617 6.10972C6.9818 6.13415 6.95285 6.15354 6.92098 6.16676C6.88911 6.17999 6.85494 6.1868 6.82043 6.1868C6.78593 6.1868 6.75176 6.17999 6.71988 6.16676C6.68801 6.15354 6.65906 6.13415 6.63469 6.10972L4.90741 4.38244C4.85821 4.33326 4.79149 4.30563 4.72193 4.30563C4.65237 4.30563 4.58565 4.33326 4.53645 4.38244L1.04883 7.86954"
          stroke="#EF6C00"
          stroke-width="1.04938"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
        <path d="M2.09863 9.6875V11.0186" stroke="#EF6C00" stroke-width="1.04938" stroke-linecap="round" stroke-linejoin="round" />
        <path d="M4.19727 7.68945V11.0181" stroke="#EF6C00" stroke-width="1.04938" stroke-linecap="round" stroke-linejoin="round" />
      </g>
      <defs>
        <clipPath id="credentials-trending-up-clip">
          <rect width="12.5926" height="12.5926" fill="white" />
        </clipPath>
      </defs>
    </svg>
    """
  end

  defp check_badge_icon(assigns) do
    ~H"""
    <svg class="w-3.5 h-3.5" viewBox="0 0 13 13" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
      <g clip-path="url(#credentials-check-badge-clip)">
        <path
          d="M8.12146 6.7627L8.91637 11.2362C8.92527 11.2889 8.91788 11.343 8.89518 11.3914C8.87248 11.4398 8.83556 11.48 8.78935 11.5068C8.74315 11.5337 8.68985 11.5457 8.6366 11.5414C8.58335 11.5371 8.53268 11.5167 8.49137 11.4828L6.61297 10.073C6.52229 10.0052 6.41213 9.96862 6.29894 9.96862C6.18575 9.96862 6.0756 10.0052 5.98492 10.073L4.10337 11.4823C4.06209 11.5161 4.01148 11.5365 3.95829 11.5408C3.90511 11.5451 3.85187 11.5331 3.8057 11.5064C3.75952 11.4796 3.72259 11.4394 3.69984 11.3912C3.67709 11.3429 3.6696 11.2888 3.67837 11.2362L4.47275 6.7627"
          stroke="#EF6C00"
          stroke-width="1.04938"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
        <path
          d="M6.29561 7.34512C8.03428 7.34512 9.44376 5.93565 9.44376 4.19698C9.44376 2.4583 8.03428 1.04883 6.29561 1.04883C4.55693 1.04883 3.14746 2.4583 3.14746 4.19698C3.14746 5.93565 4.55693 7.34512 6.29561 7.34512Z"
          stroke="#EF6C00"
          stroke-width="1.04938"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
      </g>
      <defs>
        <clipPath id="credentials-check-badge-clip">
          <rect width="12.5926" height="12.5926" fill="white" />
        </clipPath>
      </defs>
    </svg>
    """
  end

  defp ai8_seal(assigns) do
    ~H"""
    <img src="/images/ai8_seal.svg" class="w-11 h-11 shrink-0" alt="AI8 VYAASA seal" />
    """
  end

  attr :flip, :boolean, default: false

  defp laurel(assigns) do
    ~H"""
    <svg viewBox="0 0 21 34" class={["w-3 h-9.25 shrink-0 text-[#EF6C00]", @flip && "-scale-x-100"]} fill="currentColor" aria-hidden="true">
      <path d="M18.7913 32.0103C19.2247 32.4809 19.6725 32.9414 20.1423 33.3784C20.2621 33.4901 20.4125 33.7283 20.6073 33.4896C20.7863 33.2698 20.5552 33.1448 20.4316 33.0278C20.2689 32.8719 20.1053 32.7152 19.9425 32.5592C19.7779 32.4047 19.6101 32.2545 19.4357 32.1132C18.7583 31.5743 18.6851 30.8398 18.8955 30.0261C19.0938 29.2484 19.3265 28.4716 19.5365 27.7101C19.7283 27.0299 19.6599 26.4134 19.3822 25.8584C19.1959 25.4937 18.6247 25.234 18.2439 25.3605C17.7926 25.5095 17.5807 25.8716 17.4855 26.3001C17.3921 26.7183 17.3471 27.1351 17.4308 27.5492C17.5202 27.9831 17.561 28.4382 17.6274 28.8852C17.6597 29.1098 17.6947 29.3355 17.7424 29.558C17.7919 29.779 17.8523 29.9981 17.931 30.2125C17.9573 30.2844 17.9278 30.3454 17.8423 30.3877C17.6444 30.3413 17.4739 30.2209 17.3561 30.0651C16.7363 29.2314 15.9139 28.5911 15.2653 27.781C15.081 27.5468 14.9442 27.3102 14.85 27.072C14.7595 26.8306 14.7113 26.5882 14.6998 26.3449C14.6746 25.86 14.8094 25.3631 15.0399 24.8682C15.2449 24.4278 15.3897 23.989 15.5158 23.5482C15.6415 23.1074 15.7338 22.6751 15.8491 22.2362C15.9765 21.7472 15.8083 21.3504 15.5361 21.0122C15.3974 20.8437 15.2402 20.7257 15.074 20.6559C14.9081 20.5853 14.7377 20.5603 14.565 20.5837C14.221 20.6306 13.8783 20.8642 13.626 21.286C13.5481 21.4167 13.5079 21.5723 13.4763 21.7173C13.3387 22.347 13.3828 22.9791 13.447 23.6075C13.5041 24.2583 13.5278 24.9192 13.7403 25.5465C13.5151 25.6114 13.4621 25.5115 13.4031 25.4371C12.7584 24.6507 12.1685 23.8217 11.5431 23.0189C11.3433 22.7589 11.2426 22.4928 11.2157 22.2181C11.2027 22.0807 11.2089 21.9406 11.2321 21.7968C11.2575 21.6515 11.3015 21.5017 11.3591 21.3479C11.5676 20.7943 11.8045 20.2552 12.0027 19.7158C12.1028 19.4453 12.1885 19.1781 12.2658 18.9034C12.3449 18.6272 12.4069 18.3492 12.4426 18.0669C12.4909 17.6892 12.4942 17.3357 12.4402 17.0001C12.393 16.6611 12.2988 16.3345 12.1308 16.0205C11.922 15.6272 11.2148 15.5236 10.8671 16.0625C10.4306 16.7475 10.1642 17.457 10.1515 18.2436C10.1551 18.9006 10.138 19.5718 10.136 20.251C10.1387 20.36 10.1797 20.5055 10.0159 20.5538C9.89133 20.5902 9.83452 20.4778 9.77796 20.3981C9.48925 19.9664 9.20839 19.5287 8.93438 19.0851C8.79355 18.8655 8.66987 18.6366 8.54559 18.4074C8.4212 18.1786 8.2987 17.9483 8.17763 17.717C8.0927 17.5543 8.03292 17.3926 7.995 17.2315C7.96026 17.0692 7.95176 16.905 7.95907 16.7424C7.97521 16.4166 8.06582 16.0909 8.20569 15.7591C8.48771 15.0772 8.91994 14.4515 9.27557 13.8116C9.48556 13.4367 9.67886 13.0639 9.78677 12.6828C9.89886 12.2994 9.91571 11.9124 9.74879 11.5108C9.62131 11.2136 9.4331 11.0428 9.20517 11.0127C8.97808 10.9825 8.71642 11.0916 8.46863 11.3546C8.34188 11.4892 8.23243 11.633 8.14164 11.7817C8.05216 11.9298 7.97687 12.0839 7.91001 12.242C7.7773 12.5585 7.67895 12.8907 7.57047 13.2222C7.52022 13.3758 7.47376 13.5309 7.43135 13.6882C7.39261 13.8438 7.35852 14.0012 7.32772 14.162C7.26571 14.4828 7.21695 14.815 7.17899 15.1644C6.90396 14.9848 6.87489 14.7717 6.79625 14.5934C6.56471 14.088 6.37268 13.5667 6.17005 13.0495C5.96053 12.5344 5.78046 12.009 5.57792 11.491C5.49665 11.2803 5.46671 11.0948 5.5049 10.9222C5.54513 10.7493 5.64734 10.5907 5.82064 10.4358C6.37764 9.93905 6.94193 9.45699 7.48561 8.96734C7.82027 8.66508 8.10039 8.3321 8.30226 7.97843C8.40418 7.80138 8.48841 7.61798 8.55435 7.42967C8.58734 7.3354 8.61584 7.23973 8.63927 7.14262C8.66501 7.04507 8.68751 6.94575 8.70475 6.84528C8.80703 6.26058 8.46877 5.79508 7.93111 5.63477C7.51256 5.51349 6.88034 5.75021 6.53433 6.20443C6.33153 6.47304 6.19674 6.76558 6.08073 7.06918C5.96722 7.37204 5.8671 7.68709 5.76507 7.99481C5.67182 8.27296 5.61555 8.56344 5.53407 8.85197C5.4536 9.13971 5.34271 9.42727 5.16 9.69569C5.03622 9.40296 4.96297 9.09865 4.87933 8.80043C4.80059 8.50117 4.71268 8.20728 4.61456 7.91789C4.52207 7.65258 4.45185 7.38765 4.40143 7.12233C4.37647 6.98962 4.35591 6.8569 4.3413 6.724C4.32962 6.59013 4.32264 6.45645 4.32028 6.32281C4.31529 6.05478 4.32855 5.78653 4.35763 5.51674C4.38643 5.24712 4.44333 4.97371 4.50782 4.70009C4.76766 3.59754 4.95411 2.4788 4.81669 1.35786C4.77637 1.03134 4.56862 0.703437 4.29937 0.44902C4.0272 0.195577 3.68524 0.0162321 3.37283 0.00126965C2.79969 -0.0273083 2.30729 0.490004 2.17132 1.31339C2.15494 1.41501 2.15655 1.52006 2.1535 1.62343C2.11556 2.9993 2.62432 4.23903 3.36657 5.35512C3.54064 5.62705 3.78967 5.87548 3.83029 6.2022C3.85375 6.37878 3.88337 6.55395 3.91669 6.72825C3.94955 6.903 3.99555 7.07446 4.03774 7.24632L4.30071 8.27705C4.3781 8.56993 4.47212 8.86171 4.53841 9.17138C4.57194 9.32627 4.5976 9.48558 4.61249 9.65192C4.63115 9.81716 4.63791 9.98937 4.62715 10.1718C4.48487 10.0358 4.41961 9.98141 4.3654 9.91799C4.31006 9.85265 4.2533 9.78393 4.21748 9.70736C3.9633 9.15516 3.59353 8.69983 3.17259 8.29173C2.75691 7.88257 2.26766 7.52566 1.7609 7.18121C1.22416 6.81095 0.595755 6.83547 0.219246 7.20871C0.0705419 7.3573 -0.00825477 7.57353 0.000147189 7.82229C0.00723768 8.07165 0.0900045 8.3555 0.24518 8.64161C0.358503 8.84807 0.475692 9.03885 0.61222 9.21151C0.747846 9.38452 0.891825 9.54198 1.0439 9.68534C1.34742 9.97131 1.67924 10.2005 2.03672 10.3825C2.7634 10.7433 3.57607 10.9194 4.42234 11.005C4.73159 11.0356 4.92953 11.0816 5.0442 11.3493C5.21524 11.7573 5.4173 12.153 5.59754 12.5551C5.78744 12.9538 5.96252 13.3562 6.06071 13.7897C6.09718 13.9449 6.13872 14.0984 6.19271 14.2477C6.2473 14.3965 6.30742 14.5441 6.36777 14.6918C6.48921 14.9868 6.61389 15.2823 6.70961 15.5924C6.487 15.6235 6.43929 15.4993 6.35856 15.4172C6.17479 15.2307 5.98952 15.0441 5.79996 14.8603C5.61177 14.6756 5.41223 14.4967 5.22194 14.3169C4.83405 13.9605 4.41686 13.6276 3.94469 13.3409C3.53225 13.0873 3.09911 12.9753 2.61403 13.1248C2.35172 13.2058 2.15488 13.3634 2.05826 13.5605C2.01007 13.6593 1.98661 13.7676 1.99275 13.881C2.00208 13.9933 2.04082 14.1097 2.11314 14.2257C2.32707 14.5676 2.54714 14.9015 2.78381 15.2123C2.84287 15.29 2.90243 15.3666 2.96481 15.4409C3.029 15.5144 3.094 15.5862 3.16059 15.6564C3.29388 15.7962 3.43215 15.9286 3.57653 16.0512C3.86567 16.297 4.18027 16.5043 4.52949 16.658C4.88119 16.8107 5.27713 16.9059 5.71022 16.9353C6.03131 16.957 6.3479 17.018 6.66365 17.0631C6.96184 17.1059 7.21994 17.185 7.42671 17.3292C7.63315 17.4738 7.80298 17.6764 7.90584 17.9782C8.03158 18.3383 8.19449 18.6835 8.37261 19.021C8.56242 19.3528 8.76926 19.6757 8.96764 20.0017C9.10866 20.2316 9.2652 20.4523 9.40909 20.6859C9.55894 20.9161 9.69038 21.1623 9.76784 21.4562C9.54407 21.2805 9.32637 21.0943 9.10345 20.9122C8.88392 20.7286 8.67007 20.5428 8.43445 20.379C8.11862 20.1574 7.80432 19.918 7.46387 19.7196C7.29127 19.6215 7.12174 19.5289 6.9397 19.4546C6.75781 19.3805 6.56527 19.3236 6.35873 19.2915C5.89174 19.2199 5.4553 19.3269 5.21376 19.8052C4.93231 20.3666 4.99278 20.7215 5.45965 21.1636C5.71916 21.4145 6.02927 21.5592 6.35977 21.6459L7.22537 21.8778C7.51913 21.9504 7.812 22.0201 8.10455 22.0818C8.68958 22.2054 9.27341 22.2977 9.86327 22.3168C10.0087 22.3217 10.1398 22.3418 10.2582 22.3764C10.3789 22.4098 10.4885 22.4567 10.588 22.5168C10.7869 22.637 10.9477 22.8094 11.0895 23.0242C11.3134 23.3613 11.5542 23.6872 11.7853 24.019C12.0231 24.3462 12.2617 24.6728 12.4888 25.0073C12.8027 25.4494 13.1817 25.8499 13.4711 26.4343C12.6323 26.3316 12.0037 25.9787 11.3987 25.5891C11.1412 25.4185 10.8766 25.2689 10.5959 25.1506C10.3138 25.0333 10.0265 24.9402 9.70832 24.8946C9.08346 24.8028 8.41428 25.0382 8.24381 25.4468C8.02839 25.9622 8.28867 26.5659 8.93362 26.9512C9.05702 27.0262 9.19492 27.0863 9.33302 27.1214C9.66744 27.206 10.0095 27.2678 10.3463 27.3156C10.6852 27.3617 11.0181 27.3948 11.359 27.4047C12.0386 27.4253 12.7043 27.3876 13.3734 27.2791C14.0088 27.1763 14.4482 27.2528 14.7669 27.7489C15.458 28.841 16.4582 29.6681 17.3107 30.6192C17.3796 30.6958 17.5252 30.7449 17.4203 30.9455C16.5118 30.607 15.6043 30.2432 14.7062 29.8277C14.2414 29.6051 13.7614 29.5597 13.2607 29.7098C12.5206 29.9276 12.2288 30.5308 12.5871 31.2026C12.8321 31.6739 13.3341 31.7807 13.7792 31.8403C15.1768 32.0167 16.565 31.9095 17.9204 31.7502C18.2959 31.7051 18.5555 31.7478 18.7913 32.0103Z" />
    </svg>
    """
  end

  attr :student_name, :string, required: true
  attr :cert_id, :string, required: true
  attr :issued_on, :string, required: true
  attr :valid_until, :string, required: true
  attr :score, :integer, required: true
  attr :qr_url, :string, required: true

  defp certificate(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-4">
      <div class="relative w-full max-w-3xl bg-[#FFFBF5] border-2 border-orange-200 rounded-2xl p-8 sm:p-10 overflow-hidden">
        <div class="absolute inset-x-0 top-0 h-2 bg-linear-to-r from-orange-400 via-orange-500 to-orange-400"></div>

        <!-- VYAASA logo watermark -->
        <div class="pointer-events-none absolute inset-0 flex items-center justify-center select-none" aria-hidden="true">
          <img src="/images/logo.png" class="w-110 h-120 opacity-5" alt="" />
        </div>

        <div class="relative z-5 flex flex-col items-center text-center">
          <img src="/images/logo.png" class="w-18 h-20 object-contain" alt="VYAASA" />
          <p class="mt-2 text-xl font-extrabold tracking-wide text-gray-900">VYAASA CERTIFICATION</p>
          <p class="text-xs font-semibold tracking-widest text-orange-500 mt-1">CERTIFICATE OF CAREER READINESS</p>

          <div class="w-24 h-px bg-gray-300 my-5"></div>
        </div>

        <div class="relative z-10 grid grid-cols-[7.5rem_1fr_6rem] gap-6 items-start">
          <div class="w-30 flex flex-col items-center pt-1">
            <div class="relative w-26 h-26 shrink-0">
              <img src={@qr_url} class="w-26 h-26" alt="Scan to verify authenticity" />
              <img
                src="/images/vyaasa-mark.svg"
                class="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-7 h-7 rounded-full bg-white p-0.5"
                alt=""
                aria-hidden="true"
              />
            </div>
            <p class="mt-2 text-[10px] font-medium text-gray-500 text-center leading-tight whitespace-nowrap">
              Scan to Verify<br />Authenticity
            </p>
          </div>

          <div class="flex flex-col items-center text-center px-2">
            <p class="text-sm text-gray-500">This certificate is proudly presented to</p>
            <p class="mt-2 text-3xl font-bold text-[#7A1F1F] uppercase font-serif">{@student_name}</p>

            <%!-- <p class="mt-6 text-sm font-bold text-orange-600 tracking-wide">GOLD LEVEL CERTIFICATION</p> --%>
            <p class="mt-3 text-lg font-extrabold text-gray-900">OVERALL SCORE: {@score}/100</p>

            <p class="mt-3 max-w-lg text-xs text-gray-600 leading-relaxed">
              This candidate has demonstrated strong skills, including technical proficiency,
              problem-solving ability, and industry readiness, as validated by the VYAASA AI Assessment Framework.
            </p>
          </div>

          <div class="w-24 flex flex-col divide-y divide-[#EF6C00] text-center">
            <div class="py-3">
              <p class="text-[10px] font-semibold text-gray-700">Certificate ID:</p>
              <p class="text-[10px] text-gray-600 mt-0.5 wrap-break-word">{@cert_id}</p>
            </div>
            <div class="py-3">
              <p class="text-[10px] font-semibold text-gray-700">Issue Date:</p>
              <p class="text-[10px] text-gray-600 mt-0.5 wrap-break-word">{@issued_on}</p>
            </div>
            <div class="py-3">
              <p class="text-[10px] font-semibold text-gray-700">Valid Until:</p>
              <p class="text-[10px] text-gray-600 mt-0.5 wrap-break-word">{@valid_until}</p>
            </div>
            <div class="py-3">
              <p class="text-[10px] font-semibold text-gray-700">Assessment Type:</p>
              <p class="text-[10px] text-gray-600 mt-0.5 wrap-break-word">AI8 Assessment</p>
            </div>
          </div>
        </div>

        <div class="relative z-10 mt-8 flex items-center justify-center gap-16">
          <.signature name="Shreeram Dittakavi" title="CEO" image="/images/ceosig.png" />
          <.signature name="Rajya Lakshmi" title="Co-Founder" image="/images/co-foundersig.png" />
        </div>
      </div>

      <button
        type="button"
        phx-click="email_certificate"
        title="Your certificate is emailed to you as a PDF. Click to send/resend."
        class="inline-flex items-center gap-2 text-sm font-semibold px-4 py-2.5 rounded-lg text-white transition"
        style="background-color: #FF8B00;"
      >
        <.icon name="hero-envelope" class="w-4 h-4" /> Email Certificate
      </button>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :title, :string, required: true
  attr :image, :string, required: true

  defp signature(assigns) do
    ~H"""
    <div class="flex flex-col items-center">
      <div class="h-10 flex items-end justify-center">
        <img src={@image} alt={"#{@name} signature"} class="max-h-10 w-auto mix-blend-multiply" />
      </div>
      <div class="border-t border-[#EF6C00] mt-0 pt-1 text-center w-40">
        <p class="text-xs font-semibold text-gray-800">{@name}</p>
        <p class="text-[10px] text-[#EF6C00] font-medium">{@title}</p>
        <p class="text-[10px] text-[#EF6C00] font-medium">VYAASA</p>
      </div>
    </div>
    """
  end

  defp tab_class(active?) do
    base = "inline-flex items-center gap-1.5 text-sm font-semibold px-4 py-2 rounded-lg border transition"

    if active? do
      base <> " border-[#EF6C00] bg-[#EF6C00] text-white"
    else
      base <> " border-gray-200 text-gray-700 hover:bg-gray-50"
    end
  end
end
