import 'vuetify/styles'
import '@mdi/font/css/materialdesignicons.css'

import { createVuetify } from 'vuetify'
import { aliases, mdi } from 'vuetify/iconsets/mdi'
import * as components from 'vuetify/components'
import * as directives from 'vuetify/directives'


// Material Design 3 baseline palette (primary = #6750A4).
// Source: m3.material.io baseline scheme. Roles map 1:1 to Vuetify color keys
// so components can reference e.g. `color="primary-container"`.
const lightColors = {
  background: '#FFFBFE',
  'on-background': '#1C1B1F',
  surface: '#FFFBFE',
  'on-surface': '#1C1B1F',
  'surface-variant': '#E7E0EC',
  'on-surface-variant': '#49454F',
  'surface-container-lowest': '#FFFFFF',
  'surface-container-low': '#F7F2FA',
  'surface-container': '#F3EDF7',
  'surface-container-high': '#ECE6F0',
  'surface-container-highest': '#E6E0E9',
  primary: '#6750A4',
  'on-primary': '#FFFFFF',
  'primary-container': '#EADDFF',
  'on-primary-container': '#21005D',
  secondary: '#625B71',
  'on-secondary': '#FFFFFF',
  'secondary-container': '#E8DEF8',
  'on-secondary-container': '#1D192B',
  tertiary: '#7D5260',
  'on-tertiary': '#FFFFFF',
  'tertiary-container': '#FFD8E4',
  'on-tertiary-container': '#31111D',
  error: '#B3261E',
  'on-error': '#FFFFFF',
  'error-container': '#F9DEDC',
  'on-error-container': '#410E0B',
  outline: '#79747E',
  'outline-variant': '#CAC4D0',
  shadow: '#000000',
  scrim: '#000000',
  'inverse-surface': '#313033',
  'inverse-on-surface': '#F4EFF4',
  'inverse-primary': '#D0BCFF',
}

const darkColors = {
  background: '#1C1B1F',
  'on-background': '#E6E1E5',
  surface: '#1C1B1F',
  'on-surface': '#E6E1E5',
  'surface-variant': '#49454F',
  'on-surface-variant': '#CAC4D0',
  'surface-container-lowest': '#0F0D13',
  'surface-container-low': '#1D1B20',
  'surface-container': '#211F26',
  'surface-container-high': '#2B2930',
  'surface-container-highest': '#36343B',
  primary: '#D0BCFF',
  'on-primary': '#381E72',
  'primary-container': '#4F378B',
  'on-primary-container': '#EADDFF',
  secondary: '#CCC2DC',
  'on-secondary': '#332D41',
  'secondary-container': '#4A4458',
  'on-secondary-container': '#E8DEF8',
  tertiary: '#EFB8C8',
  'on-tertiary': '#492532',
  'tertiary-container': '#633B48',
  'on-tertiary-container': '#FFD8E4',
  error: '#F2B8B5',
  'on-error': '#601410',
  'error-container': '#8C1D18',
  'on-error-container': '#F9DEDC',
  outline: '#938F99',
  'outline-variant': '#49454F',
  shadow: '#000000',
  scrim: '#000000',
  'inverse-surface': '#E6E1E5',
  'inverse-on-surface': '#313033',
  'inverse-primary': '#6750A4',
}

export default createVuetify({
  components,
  directives,
  // Override the default 'lg' threshold (1280px) — on a regular laptop that
  // would flip useDisplay().mobile to true and collapse the navigation
  // drawer into a temporary overlay. We treat 'mobile' as actual phones.
  display: {
    mobileBreakpoint: 'sm',
  },
  defaults: {
    // M3 buttons are pill-shaped by default; opt out by passing `rounded`.
    VBtn: { rounded: 'pill', class: 'md-label-large' },
    VTextField: { variant: 'filled' },
    VTextarea: { variant: 'filled' },
    VSelect: { variant: 'filled' },
    VCard: { rounded: 'lg' },
  },
  theme: {
    defaultTheme:
      typeof window !== 'undefined' &&
      window.matchMedia('(prefers-color-scheme: dark)').matches
        ? 'hardhatDark'
        : 'hardhatLight',
    themes: {
      hardhatLight: { dark: false, colors: lightColors },
      hardhatDark: { dark: true, colors: darkColors },
    },
  },
  icons: {
    defaultSet: 'mdi',
    aliases,
    sets: { mdi },
  },
})
